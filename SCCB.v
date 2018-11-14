 /***************************************************
*	Module Name		:	SCCB		   
*	Engineer		:	zhangbaoliang
*	Target Device	:	EP4CE10F17C8
*	Tool versions	:	Quartus II 13.0
*	Create Date		:	2019-11-1
*	Revision		:	v1.0
*	Description		:  SCCB控制器，用于配置摄像头寄存器
**************************************************/
 module SCCB(
	Clk,
	Rst_N,
	
	Device_Addr,
	Word_Addr,
	
	Wr,
	Wr_Data,
	Wr_Data_Vaild,
	Rd,
	Rd_Data,
	Rd_Data_Vaild,
	
	SCL,
	SDA,
	
	Wr_Done,
	Rd_Done
 );
	// 系统采用的50M时钟
	parameter SYS_CLOCK=50_000_000;
	//IIC频率400K
	parameter SCL_CLOCK=400_000;
	// IIC时钟分频系数
	localparam SCL_CNT_Max=SYS_CLOCK/SCL_CLOCK;
	
	//端口定义
	input Clk;					// 系统时钟
	input Rst_N;				//系统复位
	
	input [7:0] Device_Addr;	//SCCB器件地址
	input [7:0] Word_Addr;		//SCCB寄存器地址
	
	input Wr;					//SCCB写使能
	input [7:0] Wr_Data;		//SCCB数据
	output Wr_Data_Vaild		//SCCB写数据有效标志位
	input Rd;					//SCCB读使能
	output [7:0] Rd_Data;		//SCCB数据
	output Rd_Data_Vaild		//SCCB读数据有效标志位
	
	output SCL;					//SCCB时钟
	inout SDA;					//SCCB数据
	
	output reg Wr_Done;			//对SCCB器件写完成标志位
	output reg Rd_Done;			//对SCCB器件读完成标志位
	
	
	localparam 
		IDLE 		= 10'b00_0000_0001,	//空闲状态
		WR_START	= 10'b00_0000_0010,	//写开始状态
		WR_CTRL		= 10'b00_0000_0100,	//写控制状态
		WR_WADDR	= 10'b00_0000_1000,	//写地址状态
		WR_DATA		= 10'b00_0001_0000,	//写数据状态
		RD_MSTOP	= 10'b00_0010_1000,	//读数据的中间停止状态
		RD_START	= 10'b00_0100_0010,	//读开始状态
		RD_CTRL		= 10'b00_1000_0100,	//读控制状态
		RD_DATA		= 10'b01_0001_0000,	//读数据状态
		STOP		= 10'b10_0001_0000;	//停止状态
	
	reg [9:0]Main_State;		//主状态机状态寄存器
	reg SDA_En;					//SDA数据总线控制位
	reg SDA_Reg;					//SDA数据输出寄存器
	reg W_Flag;					//SCCB写标志位
	reg R_Flag;					//SCCB读标志位
	reg FF;						//串行输出任务执行标志位
	wire [7:0] Wr_Ctrl_Word;	//写控制数据寄存器
	wire [7:0] Rd_Ctrl_Word;	//读控制数据寄存器
	reg [15:0] SCL_Cnt;			//SCL时钟计数器
	reg SCL_Vaild;				//SCCB非空闲时期
	reg SCL_High;				//SCL高电平计数器
	reg SCL_Low;				//SCL低电平计数器
	reg [7:0] Halfbit_Cnt;		//串行数据传输计数器
	reg ACK;					//ACK
	
	reg [7:0] SDA_Data_Out;		//待输出SDA串行数据
	reg [7:0] SDA_Data_In;		//SDA串行输入的数据
	
	wire Rdata_Vaild_R;			//读数据有效标志位前寄存器
	reg SCL_R;                  //SCCB SCL寄存器
	
	//读写控制位的生成
	assign Wr_Ctrl_Word={Device_Addr[7:1],1'b0};
	assign Rd_Ctrl_Word={Device_Addr[7:1],1'b1};
	//SCL的生成，为何是在此两种状态下才会是1？？？？？
	assign SCL=(Main_State==RD_MSTOP)||(Main_State==RD_START)?:1'b1:SCL_R;
	
	// SCCB数据线采用三态门进行传输
	assign SDA=SDA_En?:SDA_Reg:1'bz;
	
	
	// SCL_Vaild的生成
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
			SCL_Vaild<=1'b0;
		else if(Wr_Done||Rd_Done)
			SCL_Vaild<=1'b0;
		else if(Wr||Rd)
			SCL_Vaild<=1'b1;
		else
			SCL_Vaild<=SCL_Vaild;
	end
	
	
	//SCL计数器
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
			SCL_Cnt<=16'd0;
		else if(SCL_Vaild)
		begin
			if(SCL_Cnt==SCL_CNT_Max-1)
				SCL_Cnt<=1'b0;
			else
				SCL_Cnt<=SCL_Cnt+1'b1;
		end
		else
			SCL_Cnt<=16'd0;
	end
	
	//SCL的产生，在SCL_Cnt_Max的一半处进行翻转
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
			SCL_R<=1'b1;
		else if(SCL_Cnt==SCL_CNT_Max>>1)
			SCL_R<=1'b0;
		else if(SCL_Cnt==16'd0)
			SCL_R<=1'b0;
		else 
			SCL_R<=SCL_R;
	end
	
	
	//在高电平的地方产生脉冲，即在计数器的1/4处
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
			SCL_High<=1'b0;
		else if(SCL_Cnt==SCL_CNT_Max>>2)
			SCL_High<=1'b1;
		else 
			SCL_High<=1'b0;
	end
	
	//在低电平的地方产生脉冲，即在计数器的3/4处
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
			SCL_Low<=1'b0;
		else if(SCL_Cnt==(SCL_CNT_Max>>2)+(SCL_CNT_Max>>1))
			SCL_Low<=1'b1;
		else 
			SCL_Low<=1'b0;
	end
	always@(posedge Clk or negedge Rst_N)
	begin
		if(!Rst_N)
		begin
			Main_State<=IDLE;
			SDA_Reg<=1'b1;
			W_Flag<=1'b0;
			R_Flag<=1'b0;
			Wr_Done<=1'b0;
			Rd_Done<=1'b0;
		end
		else begin
			case(Main_State)
				IDLE:begin
					SDA_Reg<=1'b1;
					W_Flag<=1'b0;
					R_Flag<=1'b0;
					Wr_Done<=1'b0;
					Rd_Done<=1'b0;
					if(Wr)begin
						Main_State<=WR_START;
						W_Flag<=1'b1;
					end
					else if(Rd)begin
						Main_State<=RD_START;
						R_Flag<=1'b1;
					end
					else
						Main_State<=IDLE;
				end
				WR_START:begin
					if(SCL_Low)begin
						Main_State<=WR_CTRL;
						SDA_Data_Out<=Wr_Ctrl_Word;
						FF<=1'b0;
					end
					else if(SCL_High)begin
						SDA_Reg<=1b'0;
						Main_State<=WR_START;
					end
					else
						Main_State<=WR_START;
				end
				
				WR_CTRL:begin
					if(FF==1'b0)
						Send_8bit_Data;
					else begin
						if(ACK==1'b1)begin
							if(SCL_Low)begin
								Main_State<=WR_WADDR;
								FF<=1'b0;
								SDA_Data_Out<=Word_Addr;
							end
							else
								Main_State<=WR_CTRL;
						end
						else
							Main_State<=IDLE;
					end
				end
				
				WR_WADDR:begin
					if(FF==1'b0)
						Send_8bit_Data;
					else begin
						if(ACK==1'b1)begin
							if(W_Flag&&SCL_Low)begin
								Main_State<=WR_DATA;
								SDA_Data_Out<=Wr_Data;
								FF<=1'b0;
							end
							else if(R_Flag&&SCL_Low)begin
								Main_State<=RD_MSTOP;
								SDA_Reg<=1'b0;
							end
							else
								Main_State<=WR_WADDR;
						end	
							Main_State<=IDLE;
					end
				end
				
				WR_DATA:begin
					if(FF==1'b0)
						Send_8bit_Data;
					else begin
						if(ACK==1'b1)begin
							if(SCL_Low)begin
								Main_State<=STOP;
								SDA_Reg<=1'b0;
							end
							else
								Main_State<=WR_DATA;
						end
						else
							Main_State<=IDLE;
					end
				end
				RD_MSTOP:begin
					if(SCL_Low)begin
						Main_State<=RD_START;
					end
					else if(SCL_High)begin
						Main_State<=RD_MSTOP;
					end
					else
						Main_State<=RD_MSTOP;
				end
				
				RD_START:begin
					if(SCL_Low)begin
						Main_State<=RD_CTRL;
						SDA_Data_Out<=Rd_Ctrl_Word;
						FF<=1'b0;
					end
					else if(SCL_High)begin
						Main_State<=RD_START;
						SDA_Reg<=1'b0;
					end
					else
						Main_State<=RD_START;
				end
				
				RD_CTRL:begin
					if(FF==1'b0)
						Send_8bit_Data;
					else begin
						if(ACK==1'b1)begin
							if(SCL_Low)begin
								Main_State<=RD_DATA;
								FF<=1'b0;
							end
							else
								Main_State<=RD_CTRL;
						end
						else
							Main_State<=IDLE;
					end
				end
				RD_DATA:begin
					if(FF==1'b0)
						Receive_8bit_Data;
					else begin
						SDA_Reg<=1'b1;
						if(SCL_Low)begin
							Main_State<=STOP;
							SDA_Reg<=1'b0;
						end
						else
							Main_State<=RD_DATA;
					end
				end
				STOP:begin
					if(SCL_High)begin
						SDA_Reg<=1'b1;
						Main_State<=IDLE;
						if(W_Flag)
							Wr_Done<=1'b1;
						else if(R_Flag)
							Rd_Done<=1'b1;
						else
						;
						end;
					else
						Main_State<=STOP;	
				end
				default:
					Main_State<=IDLE;
			endcase
		end
	end
	
	//SDA串行接收和发送时SCl高低电平计数器
	always@(posedge Clk or negedge Rst_N)
	if(!Rst_N)
		Halfbit_Cnt<=1'b0;
	else if((Main_State==WR_CTRL)||(Main_State==WR_WADDR)||(Main_State==WR_DATA)
			||(Main_State==RD_CTRL)||(Main_State==RD_DATA))
		begin
			if(SCL_Low|SCL_High)begin
				if(Halfbit_Cnt==8'd17)
					Halfbit_Cnt<=8'd0;
				else 
					Halfbit_Cnt<=Halfbit_Cnt+8'd1;
			end
			else
				Halfbit_Cnt<=Halfbit_Cnt;
		end
	else
		Halfbit_Cnt<=8'd0;
	//数据接收方对发送方的响应检测标志位
	always@(posedge Clk or negedge Rst_N)
	if(!Rst_N)
		ACK<=1'b0;
	else if((Halfbit_Cnt==8'd16)&&SCL_High&&(SDA==1'b0))
		ACk<=1'b1;
	else if((Halfbit_Cnt==8'd17)&&SCL_Low)
		ACK<=1'b0;
	else 
		ACK<=ACK;
		
	//串行输出任务
	task Send_8bit_Data;
		if(SCL_High&&(Halfbit_Cnt==8'd16))
			FF<=1;
		else if(Halfbit_Cnt<8'd17)begin
			SDA_Reg<=SDA_Data_Out[7];
			if(SCL_Low)
				SDA_Data_Out={SDA_Data_Out[6:0],1'b0};
			else
				SDA_Data_Out<=SDA_Data_Out;
		end
		else
			;
	endtask
	//串行接收任务
		task Receive_8bit_Data;
		if(SCL_Low&&(Halfbit_Cnt==8'd15))
			FF<=1;
		else if(Halfbit_Cnt<8'd15)begin
			SDA_Reg<=SDA_Data_Out[7];
			if(SCL_High)
				SDA_Data_In={SDA_Data_In[6:0],SDA};
			else
				SDA_Data_In<=SDA_Data_In;
		end
		else
			;
	endtask
	
	//SDA三态使能SDA_En
	
	always@(*)
	begin
		case(Main_State)
			IDLE:
				SDA_En=1'b0;
			WR_START,RD_START,RD_MSTOP,STOP:
				SDA_En=1'b1;
			WR_CTRL,WR_WADDR,WR_DATA,RD_CTRL:
				if(Halfbit_Cnt<16)
					SDA_En=1'b1;
				else
					SDA_En=1'b0;
			RD_DATA:
				if(Halfbit_Cnt<16)
					SDA_En=1'b0;
				else
					SDA_En=1'b1;
			default:
				SDA_En=1'b0;
		endcase
	end
	assign Wr_Data_Vaild=((Main_State==WR_WADDR)&&(W_Flag&&SCL_Low)&&(ACK==1'b1));
	assign Rdata_Vaild_R=((Main_State==RD_DATA)&&(Halfbit_Cnt==8'15)&&SCL_Low);
	//读取数据有效标志位
	always@(posedge Clk or negedge Rst_N)
	if(!Rst_N)
		Rd_Data_Vaild<=1'b0;
	else if(Rdata_Vaild_R)
		Rd_Data_Vaild<=1'b1;
	else 
		Rd_Data_Vaild<=1'b0;
	
	//读出数据
	always@(posedge Clk or negedge Rst_N)
	if(!Rst_N)
		Rd_Data<=8'd0;
	else if(Rd_Data_Vaild)
		Rd_Data<=SDA_Data_In;
	else
		Rd_Data<=Rd_Data;
 endmodule
 
 
 
 
 
 
 
 
 