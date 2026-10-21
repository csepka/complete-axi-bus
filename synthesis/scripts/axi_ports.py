"""Single structural signal schema for synthesis adapters; no behavior.

Names and widths mirror axi_if.sv.
"""
WIDTHS={'AWVALID':'1','AWREADY':'1','AWADDR':'ADDR_W','AWPROT':'3','AWID':'ID_W','AWLEN':'8','AWSIZE':'3','AWBURST':'2',
'WVALID':'1','WREADY':'1','WDATA':'DATA_W','WSTRB':'DATA_W/8','WLAST':'1','BVALID':'1','BREADY':'1','BRESP':'2','BID':'ID_W',
'ARVALID':'1','ARREADY':'1','ARADDR':'ADDR_W','ARPROT':'3','ARID':'ID_W','ARLEN':'8','ARSIZE':'3','ARBURST':'2',
'RVALID':'1','RREADY':'1','RDATA':'DATA_W','RRESP':'2','RID':'ID_W','RLAST':'1'}
MANAGER_OUTPUTS=set('AWVALID AWADDR AWPROT AWID AWLEN AWSIZE AWBURST WVALID WDATA WSTRB WLAST BREADY ARVALID ARADDR ARPROT ARID ARLEN ARSIZE ARBURST RREADY'.split())


def expand_interfaces(source, original_module, flat_module):
    """Expand known up/down interface ports; retain all functional source text."""
    ports=[]
    for side in ['up','down']:
        for signal,width in WIDTHS.items():
            direction='input' if (signal in MANAGER_OUTPUTS)==(side=='up') else 'output'
            vector='' if width=='1' else f'[{width}-1:0] '
            ports.append(f'    {direction} logic {vector}{side}_{signal}')
    interface_ports='    axi_if.sub up,\n    axi_if.mgr down'
    if source.count(interface_ports)!=1:
        raise ValueError('Interface declaration changed; review structural expansion')
    return source.replace(f'module {original_module} #(',f'module {flat_module} #(',1).replace(
        interface_ports,',\n'.join(ports),1).replace('up.','up_').replace('down.','down_')
