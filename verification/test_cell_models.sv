`timescale 1ns/1ps
// Exhaustively compare against all binary completions of four-state inputs.
module test_cell_models;
  reg A,B,S;
  wire x1,x2,raw1,raw2;
  MUX2_X1 u1(A,B,S,x1);
  MUX2_X2 u2(A,B,S,x2);
  MUX2_X1_RAW r1(A,B,S,raw1);
  MUX2_X2_RAW r2(A,B,S,raw2);
  function automatic logic symbol(input integer code);
    case(code) 0:symbol=0;1:symbol=1;2:symbol=1'bx;3:symbol=1'bz;endcase
  endfunction
  function automatic logic oracle(input integer a,b,s);
    integer observed;
    observed=0;
    for(integer av=0;av<2;av++)
      for(integer bv=0;bv<2;bv++)
        for(integer sv=0;sv<2;sv++)
          if((a>=2 || a==av) && (b>=2 || b==bv) && (s>=2 || s==sv))
            observed=observed | (1 << (sv ? bv : av));
    case(observed) 1:oracle=0;2:oracle=1;default:oracle=1'bx;endcase
  endfunction
  initial begin
    for(integer a=0;a<4;a++) for(integer b=0;b<4;b++) for(integer s=0;s<4;s++) begin
      A=symbol(a);B=symbol(b);S=symbol(s);#1;
      if(x1 !== oracle(a,b,s) || x2 !== oracle(a,b,s))
        $fatal(1,"four-state MUX mismatch A=%b B=%b S=%b",A,B,S);
      if(a<2 && b<2 && s<2 && (x1 !== raw1 || x2 !== raw2))
        $fatal(1,"binary Liberty function changed");
    end
    A=1;B=1;S=1'bx;#1;
    if(raw1 !== 1'bx || raw2 !== 1'bx || x1 !== 1'b1 || x2 !== 1'b1)
      $fatal(1,"pessimism reproduction failed");
    $display("PASS: 128 four-state MUX cases; 16 binary equivalence cases; original pessimism reproduced");
    $finish;
  end
endmodule
