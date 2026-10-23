"""External AXI BFMs plus independent byte oracle and channel/order monitors.

The test uses a transparent fabric and independent RAM models, not axi_ram RTL.
It deliberately exercises fabric forwarding beyond the demo RAM's full-width
aligned subset. This is evidence for routing, not new demo RAM feature support.
"""
from collections import Counter, deque
import json
import logging
import math
import os
from pathlib import Path
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from cocotbext.axi import AxiBus, AxiMaster, AxiRam, AxiBurstType, AxiResp

CONFIG=json.loads(os.environ['AXI_CONFIG'])
FIELDS={'aw':'addr prot id len size burst','w':'data strb last','b':'resp id',
        'ar':'addr prot id len size burst','r':'data resp id last'}

class Monitor:
    def __init__(self,dut,port,coverage):
        self.dut,self.port,self.cov=dut,port,coverage
        self.writes,self.reads,self.wbeats=deque(),deque(),deque()
        self.stalled={}
        self.peak_w=self.peak_r=0
    def get(self,name):
        value=getattr(self.dut,self.port+'_'+name).value
        assert value.is_resolvable, f'{self.port}_{name} is X/Z during a meaningful transfer'
        return int(value)
    async def run(self):
        while True:
            await RisingEdge(self.dut.ACLK)
            if not int(self.dut.ARESETn.value):
                self.writes.clear();self.reads.clear();self.wbeats.clear();self.stalled.clear()
                continue
            for ch,fields in FIELDS.items():
                valid=self.get(ch+'valid');ready=self.get(ch+'ready')
                payload=tuple(self.get(ch+f) for f in fields.split()) if valid else None
                if ch in self.stalled:
                    assert valid and payload==self.stalled[ch],f'{self.port} {ch} changed under stall'
                if valid and not ready:
                    self.stalled[ch]=payload;self.cov['stall_'+ch]+=1
                else:self.stalled.pop(ch,None)
                if not(valid and ready):continue
                self.cov[self.port+'_'+ch]+=1
                if ch in ['aw','ar']:
                    entry={'id':self.get(ch+'id'),'left':self.get(ch+'len')+1,'done':False}
                    (self.writes if ch=='aw' else self.reads).append(entry)
                    self.cov[f'{ch}_burst_{self.get(ch+"burst")}']+=1
                    self.cov[f'{ch}_len_{self.get(ch+"len")+1}']+=1
                    self.cov[f'{ch}_size_{self.get(ch+"size")}']+=1
                elif ch=='w':
                    self.wbeats.append(self.get('wlast'))
                    if not any(not x['done'] for x in self.writes):self.cov['w_before_aw']+=1
                if ch in ['aw','w']:
                    # Independent AXI channels permit target W acceptance before
                    # AW. Pair buffered beats with addresses in acceptance order.
                    while self.wbeats:
                        pending=next((x for x in self.writes if not x['done']),None)
                        if pending is None:break
                        assert self.wbeats.popleft()==(pending['left']==1),'Incorrect WLAST'
                        pending['left']-=1;pending['done']=pending['left']==0
                elif ch=='b':
                    assert self.writes and self.writes[0]['done'],'Premature/unmatched B'
                    assert self.get('bid')==self.writes.popleft()['id'],'B ID/order mismatch'
                    self.cov[f'b_resp_{self.get("bresp")}']+=1
                elif ch=='r':
                    assert self.reads,'R without accepted AR'
                    assert self.get('rid')==self.reads[0]['id'],'R ID/order mismatch'
                    assert self.get('rlast')==(self.reads[0]['left']==1),'Incorrect RLAST'
                    self.reads[0]['left']-=1
                    if not self.reads[0]['left']:self.reads.popleft()
                    self.cov[f'r_resp_{self.get("rresp")}']+=1
            self.peak_w=max(self.peak_w,len(self.writes));self.peak_r=max(self.peak_r,len(self.reads))

def pauses(seed):
    rng=random.Random(seed)
    while True:yield rng.randrange(100)<40

@cocotb.test(timeout_time=3,timeout_unit='ms')
async def independent_axi(dut):
    cfg=CONFIG;nm,ns,word=cfg['nm'],cfg['ns'],cfg['width']//8
    rng=random.Random(cfg['seed']);cov=Counter()
    dut.ARESETn.value=0
    cocotb.start_soon(Clock(dut.ACLK,10,unit='ns').start())
    masters=[AxiMaster(AxiBus.from_prefix(dut,f'm{i}'),dut.ACLK,dut.ARESETn,reset_active_level=False) for i in range(nm)]
    rams=[AxiRam(AxiBus.from_prefix(dut,f's{i}'),dut.ACLK,dut.ARESETn,reset_active_level=False,size=65536) for i in range(ns)]
    for obj in masters+rams:
        obj.write_if.log.setLevel(logging.WARNING);obj.read_if.log.setLevel(logging.WARNING)
    monitors=[Monitor(dut,f'm{i}',cov) for i in range(nm)]+[Monitor(dut,f's{i}',cov) for i in range(ns)]
    monitor_tasks=[cocotb.start_soon(m.run()) for m in monitors]
    await ClockCycles(dut.ACLK,5)
    await Timer(1,unit='ns');dut.ARESETn.value=1
    await ClockCycles(dut.ACLK,3)

    # Independent target memory is inspected directly after writes, and reads
    # compare to byte arrays, so a shared read/write routing bug cannot self-mask.
    for m,master in enumerate(masters):
        for target,ram in enumerate(rams):
            for beats in [1,2,16,min(256,4096//word)]:
                address=target*65536+0x1000
                data=bytes(rng.randrange(256) for _ in range(beats*word))
                result=await master.write(address,data,awid=m%3)
                assert result.resp==AxiResp.OKAY
                assert ram.read(0x1000,len(data))==data
                result=await master.read(address,len(data),arid=m%3)
                assert result.resp==AxiResp.OKAY and result.data==data
                cov['directed_incr']+=1
            # Partial strobes, narrow and unaligned legal INCR forwarding.
            for size in range(int(math.log2(word))+1):
                address=target*65536+0x3011
                data=bytes(rng.randrange(256) for _ in range(19))
                before=ram.read(0x3000,64)
                assert (await master.write(address,data,size=size,awid=2)).resp==AxiResp.OKAY
                expected=before[:17]+data+before[36:]
                assert ram.read(0x3000,64)==expected
                read=await master.read(address,len(data),size=size,arid=2)
                assert read.data==data and read.resp==AxiResp.OKAY
                cov['narrow_unaligned']+=1
            for beats in [1,16]:
                address=target*65536+0x4000
                data=bytes(rng.randrange(256) for _ in range(beats*word))
                assert (await master.write(address,data,burst=AxiBurstType.FIXED,awid=1)).resp==AxiResp.OKAY
                assert ram.read(0x4000,word)==data[-word:]
                read=await master.read(address,beats*word,burst=AxiBurstType.FIXED,arid=1)
                assert read.data==data[-word:]*beats
                cov['directed_fixed']+=1
            for beats in [2,4,8,16]:
                span=beats*word;base=0x5000;offset=(beats-1)*word
                data=bytes(rng.randrange(256) for _ in range(span))
                ram.write(base,data)
                read=await master.read(target*65536+base+offset,span,burst=AxiBurstType.WRAP,arid=1)
                assert read.resp==AxiResp.OKAY and read.data==data[offset:]+data[:offset]
                payload=bytes(rng.randrange(256) for _ in range(span))
                result=await master.write(target*65536+base+offset,payload,burst=AxiBurstType.WRAP,awid=1)
                assert result.resp==AxiResp.OKAY
                assert ram.read(base,span)==payload[span-offset:]+payload[:span-offset]
                cov['directed_wrap']+=1
            # A BFM operation straddles a page; it must split legal AXI bursts.
            data=bytes(rng.randrange(256) for _ in range(4*word))
            assert (await master.write(target*65536+4096-word,data,awid=0)).resp==AxiResp.OKAY
            assert ram.read(4096-word,len(data))==data
            read=await master.read(target*65536+4096-word,len(data),arid=0)
            assert read.data==data
            cov['page_split']+=1
        miss=ns*65536+32
        assert (await master.write(miss,bytes(3*word),awid=3)).resp==AxiResp.DECERR
        assert (await master.read(miss,3*word,arid=3)).resp==AxiResp.DECERR

    # Every channel gets an independent deterministic pause stream. Multiple
    # calls enqueue overlapping IDs and changing targets before waiting.
    for i,obj in enumerate(masters+rams):
        for j,ch in enumerate([obj.write_if.aw_channel,obj.write_if.w_channel,obj.write_if.b_channel,obj.read_if.ar_channel,obj.read_if.r_channel]):
            ch.set_pause_generator(pauses(cfg['seed']+100*i+j))
    for batch in range(8):
        jobs=[];expected=[]
        for m,master in enumerate(masters):
            for slot in range(8):
                target=(slot+m+batch)%ns
                offset=m*0x1000+slot*0x200
                data=bytes(rng.randrange(256) for _ in range(rng.choice([word,2*word,16*word])))
                address=target*65536+offset
                jobs.append(cocotb.start_soon(master.write(address,data,awid=slot%3)))
                expected.append((m,target,offset,data))
        for job in jobs:assert (await job).resp==AxiResp.OKAY
        for m,t,offset,data in expected:assert rams[t].read(offset,len(data))==data
        reads=[cocotb.start_soon(masters[m].read(t*65536+offset,len(data),arid=i%3)) for i,(m,t,offset,data) in enumerate(expected)]
        # Concurrent writes use a disjoint region while these reads are active.
        writes=[cocotb.start_soon(masters[m].write(t*65536+offset+0x8000,data,awid=i%3)) for i,(m,t,offset,data) in enumerate(expected)]
        for task,(_,_,_,data) in zip(reads,expected):
            result=await task;assert result.resp==AxiResp.OKAY and result.data==data
        for task in writes:assert (await task).resp==AxiResp.OKAY
        for m,t,offset,data in expected:assert rams[t].read(offset+0x8000,len(data))==data
        cov['random_batches']+=1
    await ClockCycles(dut.ACLK,10)
    for mon in monitors:
        assert not mon.writes and not mon.reads and not mon.wbeats,'Unretired transaction'
    for channel in FIELDS:assert cov['stall_'+channel]>0, 'Missing '+channel+' stall coverage'
    assert all(mon.peak_w<=cfg['depth'] and mon.peak_r<=cfg['depth'] for mon in monitors[:nm])
    assert max(mon.peak_w for mon in monitors[:nm])==cfg['depth'],'Queue-full write coverage absent'
    assert max(mon.peak_r for mon in monitors[:nm])==cfg['depth'],'Queue-full read coverage absent'
    # Reset cancellation under stalled responses and full accepted queues.
    for obj in masters+rams:
        for ch in [obj.write_if.aw_channel,obj.write_if.w_channel,obj.write_if.b_channel,obj.read_if.ar_channel,obj.read_if.r_channel]:
            ch.set_pause_generator(None);ch.pause=False
    for m,master in enumerate(masters):
        master.write_if.b_channel.pause=True
        master.read_if.r_channel.pause=True
        for i in range(cfg['depth']+2):
            address=(m%ns)*65536+0x6000+i*word
            master.init_write(address,bytes([0x5a])*word,awid=i%3)
            master.init_read(address,word,arid=i%3)
    await ClockCycles(dut.ACLK,100)
    if cfg.get('baseline',False):
        # Original fabric accepts one transaction globally per direction.
        assert sum(len(mon.writes) for mon in monitors[:nm])==1
        assert sum(len(mon.reads) for mon in monitors[:nm])==1
        cov['reset_global_busy']+=1
    else:
        assert all(len(mon.writes)==cfg['depth'] and len(mon.reads)==cfg['depth'] for mon in monitors[:nm])
        cov['reset_full_queues']+=1
    await Timer(1,unit='ns');dut.ARESETn.value=0
    await ClockCycles(dut.ACLK,5)
    await Timer(1,unit='ns');dut.ARESETn.value=1
    for master in masters:
        master.write_if.b_channel.pause=False;master.read_if.r_channel.pause=False
    await ClockCycles(dut.ACLK,5)
    for m,master in enumerate(masters):
        address=(m%ns)*65536+0x7000
        data=bytes([m+1])*word*2
        assert (await master.write(address,data,awid=3)).resp==AxiResp.OKAY
        result=await master.read(address,len(data),arid=3)
        assert result.resp==AxiResp.OKAY and result.data==data
        cov['reset_recovery']+=1
    await ClockCycles(dut.ACLK,10)
    for mon in monitors:assert not mon.writes and not mon.reads and not mon.wbeats
    for task in monitor_tasks:task.cancel()
    Path(os.environ['AXI_COVERAGE']).write_text(json.dumps({'configuration':cfg,'bins':dict(sorted(cov.items())),
        'peak_outstanding':{m.port:{'write':m.peak_w,'read':m.peak_r} for m in monitors}},indent=2)+'\n')
