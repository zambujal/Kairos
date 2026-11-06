// mem_sim.v: as memorias do core para a simulacao (o core/mem.v com as ROMs ja' carregadas).
// No Tang o programa de arranque (core/arranque) le' do cartao a ROM do Timex e o esxDOS para estas duas
// memorias; aqui elas comecam cheias (home.hex e esx.hex na pasta onde corre a simulacao) e o faz.sh poe
// o sinal carga do core a 0 desde o inicio.

module ram_home (input clk, input [13:0] a, input we, input [7:0] d, output reg [7:0] q);
  reg [7:0] m [0:16383];
  initial $readmemh("home.hex", m);
  always @(posedge clk) begin
    if (we) m[a] <= d;
    q <= m[a];
  end
endmodule

module ram_esx (input clk, input [12:0] a, input we, input [7:0] d, output reg [7:0] q);
  reg [7:0] m [0:8191];
  initial $readmemh("esx.hex", m);
  always @(posedge clk) begin
    if (we) m[a] <= d;
    q <= m[a];
  end
endmodule

// RAM com porto A (CPU, le/escreve) e porto B (video, so le, com relogio proprio)
module ram_dp #(parameter AW = 14) (
  input clk,
  input [AW-1:0] a, input we, input [7:0] d, output reg [7:0] q,
  input clkb, input [AW-1:0] b, output reg [7:0] bq);
  reg [7:0] m [0:(1<<AW)-1] /* verilator public */;
  always @(posedge clk) begin
    if (we) m[a] <= d;
    else    q <= m[a];
  end
  always @(posedge clkb) bq <= m[b];
endmodule

// os bancos 4/6 do modo 16C do Pentagon (2 x 6K)
module ram_dp12k (
  input clk, input [13:0] a, input we, input [7:0] d,
  input clkb, input [13:0] b, output reg [7:0] bq);
  reg [7:0] m [0:12287];
  always @(posedge clk) if (we) m[a] <= d;
  always @(posedge clkb) bq <= m[b];
endmodule
