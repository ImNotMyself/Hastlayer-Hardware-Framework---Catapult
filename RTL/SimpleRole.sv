/*
Name: SimpleRole.sv
Description: DRAM loopback test. Writes data to DRAM and reads it back before looping back through PCIe.

Copyright (c) Microsoft Corporation
 
All rights reserved. 
 
MIT License
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
documentation files (the ""Software""), to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and 
to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE 
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR 
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, 
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
		
		
import ShellTypes::*;
import SL3Types::*;
		
		
typedef struct packed {
	//logic [31:0] size;
	logic        last;
	logic [15:0] slot;
	logic [3:0]  pad;
} JobContext;
		
		
module SimpleRole
(
	// User clock and reset
	input                               clk,
	input                               rst, 
		
	// Simplified Memory interface
	output MemReq                       mem_reqs        [1:0],
	input                               mem_req_grants  [1:0],
	input MemResp                       mem_resps       [1:0],
	output                              mem_resp_grants [1:0],
		
	// PCIe Slot DMA interface
	input PCIEPacket                    pcie_packet_in,
	output                              pcie_full_out,
		
	output PCIEPacket                   pcie_packet_out,
	input                               pcie_grant_in,
		
	// Soft register interface
	input SoftRegReq                    softreg_req,
	output SoftRegResp                  softreg_resp,
		
	// SerialLite III interface
	output SL3DataInterface             sl_tx_out           [3:0],
	input                               sl_tx_full_in       [3:0],
	output SL3OOBInterface              sl_tx_oob_out       [3:0],
	input                               sl_tx_oob_full_in   [3:0],
		
	input SL3DataInterface              sl_rx_in            [3:0],
	output                              sl_rx_grant_out     [3:0],
	input SL3OOBInterface               sl_rx_oob_in        [3:0],
	output                              sl_rx_oob_grant_out [3:0]
);  	
		
	// Disable SL3 links
	genvar i;
	generate
		for(i = 0; i < 4; i=i+1) begin: disableSL3
			assign sl_tx_out[i] = '{valid: 1'b0, data: 128'b0, last: 1'b0};
			assign sl_tx_oob_out[i] = '{valid: 1'b0, data: 15'b0};
			
			assign sl_rx_grant_out[i] = 1'b0;
			assign sl_rx_oob_grant_out[i] = 1'b0;
		end
	endgenerate
		
	// Set up DRAM interleaver
	DramInterleaverConfig dramConfig;
	MemReq  mem_interleaved_req;
	wire    mem_interleaved_req_grant;
	MemResp mem_interleaved_resp;
	reg     mem_interleaved_resp_grant;
	/*
	assign mem_reqs[0] = mem_interleaved_req;
	assign mem_interleaved_req_grant = mem_req_grants[0];
	assign mem_interleaved_resp = mem_resps[0];
	assign mem_resp_grants[0] = mem_interleaved_resp_grant;
	
	// Disable channel 1 for now
	assign mem_reqs[1] = '{valid: 1'b0, isWrite: 1'b0, addr: 64'b0, data: 512'b0};
	assign mem_resp_grants[1] = 1'b0;
	*/
		
	//Hast_ip_wrapper signals
	//logic [511:0] Hast_IP_Data_in_sig;
	logic [63:0] Hast_IP_Read_Addr_out_sig;
	logic [63:0] Hast_IP_Write_Addr_out_sig;
	//logic [511:0] Hast_IP_Data_out_sig;
		 
	logic [511:0] Hast_IP_Data_in;
	logic [31:0] Hast_IP_Read_Addr_out;
	logic [31:0] Hast_IP_Write_Addr_out;
	logic [511:0] Hast_IP_Data_out; 
	logic [31:0] Hast_IP_MemberID_in;
	logic [511:0] Hast_IP_Control_Packet_out;
	logic Hast_IP_Started_in;
	logic Hast_IP_Write_Ena_out;
	logic Hast_IP_Read_Ena_out;
	logic Hast_IP_Reads_Done_in;
	logic Hast_IP_Writes_Done_in;
	logic Hast_IP_Finished_out;
		
		
	DramInterleaver interleaver
	(
	// User clock and reset
	.clk(clk),
	.rst(rst),
		
	// Config
	.config_in(dramConfig),
		
	// Input interface
	.mem_req_in(mem_interleaved_req),
	.mem_req_grant_out(mem_interleaved_req_grant),
	.mem_resp_out(mem_interleaved_resp),
	.mem_resp_grant_in(mem_interleaved_resp_grant),
		
	// Output interfaces
	.mem_req_c0_out(mem_reqs[0]),
	.mem_req_grant_c0_in(mem_req_grants[0]),
	.mem_resp_c0_in(mem_resps[0]),
	.mem_resp_grant_c0_out(mem_resp_grants[0]),
		
	.mem_req_c1_out(mem_reqs[1]),
	.mem_req_grant_c1_in(mem_req_grants[1]),
	.mem_resp_c1_in(mem_resps[1]),
	.mem_resp_grant_c1_out(mem_resp_grants[1])
	);
		
		Hast_ip_wrapper Hast_ip_wrapper_inst
	(
		.Hast_IP_Clk_in             (clk),      
		.Hast_IP_Rst_in             (rst),
		.Hast_IP_MemberID_in        (Hast_IP_MemberID_in),
		.Hast_IP_Data_in            (Hast_IP_Data_in),
		.Hast_IP_Data_out           (Hast_IP_Data_out),
		.Hast_IP_Read_Addr_out      (Hast_IP_Read_Addr_out),
		.Hast_IP_Read_Ena_out       (Hast_IP_Read_Ena_out),
		.Hast_IP_Write_Addr_out     (Hast_IP_Write_Addr_out),
		.Hast_IP_Write_Ena_out      (Hast_IP_Write_Ena_out),
		.Hast_IP_Started_in         (Hast_IP_Started_in),
		.Hast_IP_Finished_out       (Hast_IP_Finished_out),
		.Hast_IP_Reads_Done_in      (Hast_IP_Reads_Done_in),
		.Hast_IP_Writes_Done_in     (Hast_IP_Writes_Done_in),
		.Hast_IP_Control_Packet_out (Hast_IP_Control_Packet_out)
	);
		
	// Softreg config
	always@* begin
		softreg_resp = '{valid:1'b0, data: 64'b0};
		dramConfig = '{valid: 1'b0, mode: CHAN0_ONLY};
				
		// Read counter values
		if(softreg_req.valid && !softreg_req.isWrite) begin
			case(softreg_req.addr)
				default: softreg_resp = '{valid: 1'b1, data: 32'd1000+softreg_req.addr};
			endcase
		end
			
		// Control FSM state
		else if(softreg_req.valid && softreg_req.isWrite) begin
			case(softreg_req.addr)
				32'd600: dramConfig = '{valid: 1'b1, mode: CHAN0_ONLY};
				32'd700: dramConfig = '{valid: 1'b1, mode: CHAN1_ONLY};
				32'd800: dramConfig = '{valid: 1'b1, mode: INTERLEAVED};
				default: dramConfig = '{valid: 1'b0, mode: CHAN0_ONLY};
			endcase
		end
	end
		
	wire       loopbackQ_enq;
	PCIEPacket loopbackQ_in;
	wire       loopbackQ_full;
	PCIEPacket loopbackQ_out;
	wire       loopbackQ_empty;
	reg        loopbackQ_deq;
	logic      pcireadstate;
		
	assign loopbackQ_enq = pcie_packet_in.valid && !loopbackQ_full;
	assign loopbackQ_in = pcie_packet_in;
	assign pcie_full_out = loopbackQ_full;
		
	FIFO
	#(
		.WIDTH                  ($bits(PCIEPacket)),
		.LOG_DEPTH              (4)//original was 4
	)
	LoopbackQ
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (loopbackQ_enq),
		.data                   (loopbackQ_in),
		.full                   (loopbackQ_full),
		.q                      (loopbackQ_out),
		.empty                  (loopbackQ_empty),
		.rdreq                  (loopbackQ_deq),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
	//----MemberID_Fifo---------- 
	logic MemberID_Fifo_full;
	logic MemberID_Fifo_write;
	logic MemberID_Fifo_read;
	logic MemberID_Fifo_empty;
	logic [64:0] MemberID_Fifo_data_in;
	logic [64:0] MemberID_Fifo_data_out;
	logic memberidstate;
	
	assign MemberID_Fifo_write   = memberidstate && !MemberID_Fifo_full;
	assign MemberID_Fifo_data_in = {Hast_IP_Read_Addr_out_sig , memberidstate};
		 
	FIFO
	#(
		.WIDTH                  (65),
		.LOG_DEPTH              (1)//original was 4
	)
	MemberID_FIFO
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (MemberID_Fifo_write),
		.data                   (MemberID_Fifo_data_in),
		.full                   (MemberID_Fifo_full),
		.q                      (MemberID_Fifo_data_out),
		.empty                  (MemberID_Fifo_empty),
		.rdreq                  (MemberID_Fifo_read),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
	//----Number_Iter_Fifo----------
		    
	logic Number_Iter_Fifo_full;
	logic Number_Iter_Fifo_write;
	logic Number_Iter_Fifo_read;
	logic Number_Iter_Fifo_empty;
	logic [64:0] Number_Iter_Fifo_data_in;
	logic [64:0] Number_Iter_Fifo_data_out;
	logic numberiterstate;
		
	assign Number_Iter_Fifo_write   = numberiterstate && !Number_Iter_Fifo_full;
	assign Number_Iter_Fifo_data_in = {Hast_IP_Read_Addr_out_sig , numberiterstate};
		 
	FIFO
	#(
		.WIDTH                  (65),
		.LOG_DEPTH              (1)//original was 4
	)
	Number_Iter_FIFO
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (Number_Iter_Fifo_write),
		.data                   (Number_Iter_Fifo_data_in),
		.full                   (Number_Iter_Fifo_full),
		.q                      (Number_Iter_Fifo_data_out),
		.empty                  (Number_Iter_Fifo_empty),
		.rdreq                  (Number_Iter_Fifo_read),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
	//----Hast_IP_Data_In_FIFO----------
		
	logic Hast_IP_Data_In_FIFO_full;
	logic Hast_IP_Data_In_FIFO_write;
	logic Hast_IP_Data_In_FIFO_read;
	logic Hast_IP_Data_In_FIFO_empty;
	logic [64:0] Hast_IP_Data_In_FIFO_data_in;
	logic [64:0] Hast_IP_Data_In_FIFO_data_out;
	logic readdatastate;
		
	assign Hast_IP_Data_In_FIFO_write = Hast_IP_Read_Ena_out && !Hast_IP_Data_In_FIFO_full;
	assign Hast_IP_Data_In_FIFO_data_in = {Hast_IP_Read_Addr_out_sig , readdatastate};
		 
	FIFO
	#(
		.WIDTH                  (65),
		.LOG_DEPTH              (4)//original was 4
	)
	Hast_IP_Data_In_FIFO
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (Hast_IP_Data_In_FIFO_write),
		.data                   (Hast_IP_Data_In_FIFO_data_in),
		.full                   (Hast_IP_Data_In_FIFO_full),
		.q                      (Hast_IP_Data_In_FIFO_data_out),
		.empty                  (Hast_IP_Data_In_FIFO_empty),
		.rdreq                  (Hast_IP_Data_In_FIFO_read),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
	//----Hast_IP_Data_Out_FIFO----------
		
	logic Hast_IP_Data_Out_FIFO_full;
	logic Hast_IP_Data_Out_FIFO_write;
	logic Hast_IP_Data_Out_FIFO_read;
	logic Hast_IP_Data_Out_FIFO_empty;
	logic [576:0] Hast_IP_Data_Out_FIFO_data_in;
	logic [576:0] Hast_IP_Data_Out_FIFO_data_out;
	logic writedatastate;
		
	assign Hast_IP_Data_Out_FIFO_write = Hast_IP_Write_Ena_out && !Hast_IP_Data_Out_FIFO_full;
	assign Hast_IP_Data_Out_FIFO_data_in = {Hast_IP_Data_out, Hast_IP_Write_Addr_out_sig, writedatastate};
	 
	FIFO
	#(
		.WIDTH                  (577),
		.LOG_DEPTH              (4)//original was 4
	)
	Hast_IP_Data_Out_FIFO
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (Hast_IP_Data_Out_FIFO_write),
		.data                   (Hast_IP_Data_Out_FIFO_data_in),
		.full                   (Hast_IP_Data_Out_FIFO_full),
		.q                      (Hast_IP_Data_Out_FIFO_data_out),
		.empty                  (Hast_IP_Data_Out_FIFO_empty),
		.rdreq                  (Hast_IP_Data_Out_FIFO_read),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
		
	logic Hast_IP_PERF_FIFO_write;
	logic Hast_IP_PERF_FIFO_read;
	logic [511:0] Hast_IP_PERF_FIFO_data_in;
	logic [511:0] Hast_IP_PERF_FIFO_data_out;
	logic Enable_Performance_fifo_write;
	logic Hast_IP_PERF_FIFO_full;
	logic Hast_IP_PERF_FIFO_empty;
		 
	assign Hast_IP_PERF_FIFO_data_in = Hast_IP_Control_Packet_out;
	assign Hast_IP_PERF_FIFO_write = Enable_Performance_fifo_write;
		 
	FIFO
	#(
		.WIDTH                  (512),
		.LOG_DEPTH              (2)//original was 4
	)
	Hast_IP_PERF_FIFO
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (Hast_IP_PERF_FIFO_write),
		.data                   (Hast_IP_PERF_FIFO_data_in),
		.full                   (Hast_IP_PERF_FIFO_full),
		.q                      (Hast_IP_PERF_FIFO_data_out),
		.empty                  (Hast_IP_PERF_FIFO_empty),
		.rdreq                  (Hast_IP_PERF_FIFO_read),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
		    
	reg        jobRespQ_enq;
	JobContext jobRespQ_in;
	wire       jobRespQ_full;
	JobContext jobRespQ_out;
	wire       jobRespQ_empty;
	reg        jobRespQ_deq;
		    
	// Needs to be sized to be at least as large as a 64KB job to prevent deadlock
	// 64KB/(128/8) = 4K entries
	// I'm sizing it to store 2 jobs (2^13 = 8K)
		    
	FIFO
	#(
		.WIDTH                  ($bits(JobContext)),
		.LOG_DEPTH              (13)//original was 13
	)
	JobRespQ
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (jobRespQ_enq),
		.data                   (jobRespQ_in),
		.full                   (jobRespQ_full),
		.q                      (jobRespQ_out),
		.empty                  (jobRespQ_empty),
		.rdreq                  (jobRespQ_deq),
		.almost_full            (),
		.almost_empty           (),
		.usedw                  ()
	);
		
	// Stream from PCIe queue to DRAM
		
	typedef enum {
		WRITE,
		HAST_MEMBERID_AND_STARTED,
		HAST_READ_NUMBER_ITER,
		//HAST_RELEASE_READS_DONE,
		HAST_READ_DATA,
		//HAST_RELEASE_READS_DONE2,
		HAST_WRITE_DATA,
		HAST_RELEASE_WRITES_DONE,
		HAST_FINISH,
		HAST_WRITE_CONTROL_SLOT,
		READ,        
		FINISHED
	} FSMState;
		 
	FSMState state;
	FSMState next_state;
		
	reg[63:0] writeAddr;
	reg[63:0] next_writeAddr;
	reg[63:0] readAddr;
	reg[63:0] next_readAddr;
	reg[31:0] jobSize;
	reg[31:0] next_jobSize;
		    
	assign Hast_IP_Read_Addr_out_sig[63:0]  = {32'b0 , Hast_IP_Read_Addr_out};
	assign Hast_IP_Write_Addr_out_sig[63:0] = {32'b0 , Hast_IP_Write_Addr_out};
		 
	//------------------
	//LOOPBACK STM
	//------------------
		 
	always@* begin
		next_state = state;
		next_writeAddr = writeAddr;
		next_readAddr = readAddr;
		next_jobSize = jobSize;
		
		//PCI_packetout--
		//mem_interleaved_resp_grant = 1'b0;
		// jobRespQ_deq = 1'b0;
		//readAddr = 64'b0;
		// pcie_packet_out = '{valid: 1'b0, data: 512'b0, slot: 16'b0, pad: 4'b0, last: 1'b0};
			//-----
			
		mem_interleaved_req = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0};
		 
		loopbackQ_deq = 1'b0;
		
		jobRespQ_enq = 1'b0;
		jobRespQ_in = '{last: 1'b0, slot: 16'b0, pad: 4'b0};
		
		
		Hast_IP_Reads_Done_in  <= 1'b0;
		Hast_IP_Writes_Done_in <= 1'b0;
		Enable_Performance_fifo_write <= 1'b0;
		Hast_IP_PERF_FIFO_read <= 1'b0;    
		                                              
		if(state == WRITE) begin
			Hast_IP_Started_in     <= 1'b0;
			memberidstate          <= 1'b0;
			numberiterstate        <= 1'b0;
			readdatastate          <= 1'b0;
			writedatastate         <= 1'b0;
			pcireadstate           <= 1'b0;
				
			if(!loopbackQ_empty && !jobRespQ_full) begin
				mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b1, addr: writeAddr, data: loopbackQ_out.data};
					
				if(mem_interleaved_req_grant) begin
					next_writeAddr = writeAddr + 64'd64;
					next_jobSize = jobSize + 32'd1;
					loopbackQ_deq = 1'b1;
						
					jobRespQ_enq = 1'b1;
					jobRespQ_in = '{last: loopbackQ_out.last, slot: loopbackQ_out.slot, pad: loopbackQ_out.pad};
						    
					if(loopbackQ_out.last) begin
						next_state = HAST_MEMBERID_AND_STARTED; 
					end
				end
			end
		end
			
		else if(state == HAST_MEMBERID_AND_STARTED) begin   
			memberidstate   <= 1'b1;  
			numberiterstate <= 1'b0;
			readdatastate   <= 1'b0;
			writedatastate  <= 1'b0;
			pcireadstate    <= 1'b0;
			mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b0, addr: MemberID_Fifo_data_out[64:1], data: 512'b0};           
			if(mem_interleaved_req_grant) begin   
				//Hast_IP_Reads_Done_in <= 1'b1;
				Hast_IP_Started_in <= 1'b1;
				next_state = HAST_READ_NUMBER_ITER;
			end
		end
			        
		else if(state == HAST_READ_NUMBER_ITER) begin
			numberiterstate <= 1'b1;
			memberidstate   <= 1'b0;
			readdatastate   <= 1'b0; 
			writedatastate  <= 1'b0;
			pcireadstate    <= 1'b0;
			//if (Hast_IP_Read_Ena_out == 1'b1) begin
				mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b0, addr: Number_Iter_Fifo_data_out[64:1], data: 512'b0};           
				if(mem_interleaved_req_grant) begin
					Hast_IP_Reads_Done_in <= 1'b1;
					next_state = HAST_READ_DATA;//HAST_RELEASE_READS_DONE;
				end
			//end
		end
		       
		/*else if(state == HAST_RELEASE_READS_DONE) begin
			numberiterstate <= 1'b0;
			memberidstate   <= 1'b0;
			readdatastate   <= 1'b0;
			writedatastate  <= 1'b0;
			pcireadstate    <= 1'b0;
			if (Hast_IP_Read_Ena_out == 1'b0) begin
				Hast_IP_Reads_Done_in <= 1'b0;
				next_state = HAST_READ_DATA;
			end
		end*/
		
		else if(state == HAST_READ_DATA) begin
			numberiterstate <= 1'b0;
			memberidstate   <= 1'b0;
			readdatastate   <= 1'b1;
			writedatastate  <= 1'b0;
			pcireadstate    <= 1'b0;
			//if (Hast_IP_Read_Ena_out == 1'b1) begin
				mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b0, addr: Hast_IP_Data_In_FIFO_data_out[64:1], data: 512'b0};           
				if(mem_interleaved_req_grant) begin
					Hast_IP_Reads_Done_in <= 1'b1;
					next_state = HAST_WRITE_DATA;//HAST_RELEASE_READS_DONE2;
				end
			//end
		end
		
		// else if(state == HAST_RELEASE_READS_DONE2) begin 
		//	if (Hast_IP_Read_Ena_out == 1'b0) begin
		//		Hast_IP_Reads_Done_in <= 1'b0;
		//		next_state = HAST_WRITE_DATA;
		//	end
		//end 
		
		else if(state == HAST_WRITE_DATA) begin  
			numberiterstate <= 1'b0;
			memberidstate   <= 1'b0;
			readdatastate   <= 1'b0;
			writedatastate  <= 1'b1;
			pcireadstate    <= 1'b0;
			Hast_IP_Reads_Done_in  <= 1'b1;
			//mem_interleaved_resp_grant = 1'b0;  
			if(!Hast_IP_Data_Out_FIFO_empty && !Hast_IP_Data_Out_FIFO_full) begin
				//Hast_IP_Data_Out_FIFO_read <= 1'b1;
				//if (Hast_IP_Write_Ena_out == 1'b1) begin
					mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b1, addr: Hast_IP_Data_Out_FIFO_data_out[64:1], data: Hast_IP_Data_Out_FIFO_data_out[576:65]};   
					if(mem_interleaved_req_grant) begin 
						//Hast_IP_Data_Out_FIFO_read <= 1'b1;
						Hast_IP_Writes_Done_in <= 1'b1;
						//mem_interleaved_resp_grant = 1'b1; 
						next_state = HAST_RELEASE_WRITES_DONE;
					end
				//end
			end
		end
		
		else if(state == HAST_RELEASE_WRITES_DONE) begin
			//if (Hast_IP_Write_Ena_out == 1'b0) begin
				Hast_IP_Writes_Done_in <= 1'b0;
				next_state = HAST_FINISH;                                                                                  
			//end                                                                                                            
		end
		  
		else if(state == HAST_FINISH) begin  
			if (Hast_IP_Finished_out == 1'b1) begin
				Enable_Performance_fifo_write <= 1'b1; 
				next_state = HAST_WRITE_CONTROL_SLOT;
			end              
			else if (Hast_IP_Finished_out == 1'b0) begin
				next_state = HAST_READ_DATA;
			end
		end
		
		else if(state == HAST_WRITE_CONTROL_SLOT) begin 
			Enable_Performance_fifo_write <= 1'b0;
			//mem_interleaved_resp_grant = 1'b0;
			if(!Hast_IP_PERF_FIFO_empty && !Hast_IP_PERF_FIFO_full) begin
				mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b1, addr: 64'd0, data: Hast_IP_PERF_FIFO_data_out};               
				if(mem_interleaved_req_grant) begin
					Hast_IP_PERF_FIFO_read <= 1'b1;
					//if (mem_interleaved_resp.valid == 1'b1) begin
					//mem_interleaved_resp_grant = 1'b1;
					next_state = READ; 
					//end
				end
			end
		end
 		
		else if(state == READ) begin
			numberiterstate <= 1'b0;
			memberidstate   <= 1'b0; 
			readdatastate   <= 1'b0;
			writedatastate  <= 1'b0;
			pcireadstate    <= 1'b1;
			mem_interleaved_req = '{valid: 1'b1, isWrite: 1'b0, addr: readAddr, data: 512'b0};
			if(mem_interleaved_req_grant) begin
				next_readAddr = readAddr + 64'd64;
				next_jobSize = jobSize - 32'd1;
				if(next_jobSize == 32'd0) begin
					next_state = FINISHED;
				end
			end
		end
				  
		else if(state == FINISHED) begin
		end
	end
		        
	always@(posedge clk) begin
		if(rst) begin
			state <= WRITE;
			writeAddr <= 64'b0;
			readAddr <= 64'b0;
			jobSize <= 32'b0;
		end
		else begin
			state <= next_state;
			writeAddr <= next_writeAddr;
			readAddr <= next_readAddr;
			jobSize <= next_jobSize;
		end
	end
		
		
	// Wait for reads from DRAM to return and write out to PCIe
		
	//wire readRespJob_last = !jobRespQ_empty && ((readRespJobSize + 1) == jobRespQ_out.size);
		  
	always@* begin
		if(rst) begin
			Hast_IP_MemberID_in  <= 32'b0;
			Hast_IP_Data_in     <= 512'b0;
		end
		else begin
			//Hast_IP_MemberID_in <= 32'b1;
			mem_interleaved_resp_grant = 1'b0;
			jobRespQ_deq = 1'b0;
			MemberID_Fifo_read = 1'b0;
			Number_Iter_Fifo_read = 1'b0;
			Hast_IP_Data_In_FIFO_read = 1'b0;
			Hast_IP_Data_Out_FIFO_read = 1'b0;
				 
				  
			pcie_packet_out = '{valid: 1'b0, data: 512'b0, slot: 16'b0, pad: 4'b0, last: 1'b0};
				  
			//if(mem_interleaved_resp.valid && !MemberID_Fifo_empty && (memberidstate == 1'b1)) begin 
			if(mem_interleaved_resp.valid && !MemberID_Fifo_empty && (MemberID_Fifo_data_out[0] == 1'b1)) begin
				MemberID_Fifo_read = 1'b1;
				Hast_IP_MemberID_in = mem_interleaved_resp.data[31:0];
				//if (Hast_IP_Read_Ena_out == 1'b1) begin
					Hast_IP_Data_in = mem_interleaved_resp.data;
				//	Hast_IP_Reads_Done_in <= 1'b1;
				//end
				mem_interleaved_resp_grant = 1'b1;
			end
				  
			//if(mem_interleaved_resp.valid && !Number_Iter_Fifo_empty && (numberiterstate == 1'b1)) begin 
			if(mem_interleaved_resp.valid && !Number_Iter_Fifo_empty && (Number_Iter_Fifo_data_out[0] == 1'b1)) begin
				Number_Iter_Fifo_read = 1'b1;
				Hast_IP_Data_in = mem_interleaved_resp.data;
				//if (Hast_IP_Read_Ena_out == 1'b1) begin
					mem_interleaved_resp_grant = 1'b1;
				//end
				//Hast_IP_Reads_Done_in <= 1'b1;
			end
			
			if(mem_interleaved_resp.valid && !Hast_IP_Data_In_FIFO_empty && (Hast_IP_Data_In_FIFO_data_out[0] == 1'b1)) begin
					Hast_IP_Data_In_FIFO_read = 1'b1;
					Hast_IP_Data_in = mem_interleaved_resp.data;
					mem_interleaved_resp_grant = 1'b1;
					//Hast_IP_Reads_Done_in <= 1'b1;
				//end
			end
			
			if(mem_interleaved_resp.valid && !Hast_IP_Data_Out_FIFO_empty && (Hast_IP_Data_Out_FIFO_data_out[0] == 1'b1)) begin
					Hast_IP_Data_Out_FIFO_read = 1'b1;
					mem_interleaved_resp_grant = 1'b1;
			end
			
			if(mem_interleaved_resp.valid && !jobRespQ_empty && (pcireadstate == 1'b1)) begin
					pcie_packet_out = '{valid: 1'b1, data: mem_interleaved_resp.data, slot: jobRespQ_out.slot, pad: jobRespQ_out.pad, last: jobRespQ_out.last};
					
					if(pcie_grant_in) begin
						mem_interleaved_resp_grant = 1'b1;
						jobRespQ_deq = 1'b1;
					end
			end
		end
	end
	
endmodule
