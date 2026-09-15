// SPDX-License-Identifier: GPL-3.0-or-later
//
// snac_psx: what happens to the user port when snac_enable changes.
//
// menu.sv gives the user port one tenant at a time -- PSX pads or MT32-pi --
// and switches between them with four combinational assignments:
//
//   assign USER_OUT = snac_enable ? snac_user_out : {5'b11111, UART_RXD, 1'b1};
//   assign UART_TXD = snac_enable ? 1'b1 : midi_rx;
//
// The mux itself is physics, as the comment there says. What nothing checked is
// the reader underneath it: snac_enable can change at any moment, including in
// the middle of a poll, and the reader is then driving a bus it no longer owns
// until its own state machine notices. If it keeps ATT low or leaves CLK
// parked low, the MT32-pi that has just been handed the port sees a line held
// down by the tenant that moved out.
//
// That is what this bench covers, and it deliberately covers it on snac_psx.v
// rather than on menu.sv's assigns: the module is what has state. The assigns
// have none, and a bench that re-declared them would be testing its own copy.
//
// A separate file from tb_snac_psx.sv on purpose -- that one is vendored from
// the AmigaCD core (see rtl/snac_psx.vendor) and editing it here would diverge
// the two copies. This one is ours, and it COMPILES the vendored file only to
// borrow its psx_pad model: -s picks this top, so tb_snac_psx itself is not
// elaborated. Reusing the model beats copying it -- a second copy of a device
// model is a second thing to keep true.
//
// Runs under Icarus:
//   iverilog -g2012 -s tb_snac_enable -o tb \
//       ../../snac_psx.v tb_snac_psx.sv tb_snac_enable.sv && vvp tb

`timescale 1ns / 1ps

module tb_snac_enable;

	parameter integer CLK_KHZ = 100000;   // what menu.sv instantiates

	localparam real HALF_NS = 1000000.0 / (2.0 * CLK_KHZ);

	reg clk = 0;
	always #(HALF_NS) clk = ~clk;

	reg reset  = 1;
	reg enable = 0;

	wire [6:0] user_out;
	wire [15:0] pad0, pad1;
	wire [31:0] axes0, axes1;
	wire [7:0]  id0, id1;

	// A DualShock on port 1, X held down and both sticks off centre. Most checks
	// here are about what the reader DRIVES, but the last three are about what it
	// FORGETS, and those need something non-default to exist first: the first
	// version of this bench checked pad0 == 0 and axes0 == centre after a disable
	// with no pad present, which passes against a reader that clears nothing.
	// Analog rather than digital for the same reason -- a digital pad's axes
	// read centre anyway, so they cannot show a missing re-centre.
	reg p0_present = 1;

	wire dat0, ack0_n;
	wire [6:0] user_in = { 2'b11, dat0, ack0_n, 3'b111 };

	psx_pad pad_a (
		.present(p0_present), .id(8'h73), .nbytes(4'd9),
		.d3(8'hFF), .d4(8'hBF),                       // X pressed, active low
		.d5(8'h12), .d6(8'h34), .d7(8'h56), .d8(8'h78),
		.glitch_only(1'b0),
		.att_n(att0_n), .sclk(sclk), .dat(dat0), .ack_n(ack0_n)
	);

	// Pin map, from snac_psx.v's user_out assign: [5] CLK, [4] DAT, [3] ACK,
	// [2] CMD, [1] ~ATT port 1, [0] ~ATT port 2.
	wire sclk   = user_out[5];
	wire cmd    = user_out[2];
	wire att0_n = user_out[1];
	wire att1_n = user_out[0];

	snac_psx #(.CLK_KHZ(CLK_KHZ), .BAUD_KHZ(250)) dut (
		.clk(clk), .reset(reset), .enable(enable),
		.user_in(user_in), .user_out(user_out),
		.pad0(pad0), .pad1(pad1), .axes0(axes0), .axes1(axes1),
		.id0(id0), .id1(id1)
	);

	// The port is idle when both ATTs are released and clock and command sit
	// high. This is the state MT32-pi needs the pins left in.
	wire bus_idle = att0_n && att1_n && sclk && cmd;

	integer errors = 0;

	// Named chk rather than expect: `expect` is a SystemVerilog keyword.
	task chk(input [511:0] what, input cond);   // 511: a 256-bit arg silently CHOPS the front off a long label
		begin
			if (!cond) begin
				$display("FAIL: %0s (att0_n=%b att1_n=%b sclk=%b cmd=%b)",
				         what, att0_n, att1_n, sclk, cmd);
				errors = errors + 1;
			end else begin
				$display("ok:   %0s", what);
			end
		end
	endtask

	// Wait until the reader is visibly mid-frame: ATT asserted on either port.
	// Returns 0 if it never gets there, so a reader that never starts fails the
	// check that wanted it started rather than hanging the bench.
	task wait_active(output started);
		integer n;
		begin
			started = 0;
			for (n = 0; n < 2000000 && !started; n = n + 1) begin
				@(posedge clk);
				if (!att0_n || !att1_n) started = 1;
			end
		end
	endtask

	integer n;
	reg     started;
	reg     saw_activity;

	initial begin
		repeat (20) @(posedge clk);
		reset = 0;
		repeat (20) @(posedge clk);

		// ---- 1. disabled: the port is left alone ---------------------------
		// Before anything else, the state every other core on this hardware
		// depends on. snac_enable is 0 whenever MT32-pi has the port.
		chk("disabled, bus left idle", bus_idle);

		// And it stays idle -- this is a level, not an edge, so a reader that
		// started a frame anyway would show up here.
		saw_activity = 0;
		for (n = 0; n < 200000; n = n + 1) begin
			@(posedge clk);
			if (!bus_idle) saw_activity = 1;
		end
		chk("disabled, still idle 200k cycles later", !saw_activity);

		// ---- 2. enable: the reader takes the bus ---------------------------
		enable = 1;
		wait_active(started);
		chk("enabled, reader starts a frame", started);

		// ---- 3. disable mid-frame: the bus goes back immediately -----------
		// The case the mux comment implies but nothing enforced. ATT is low
		// right now; dropping enable has to release it, not wait for the frame
		// to finish -- MT32-pi is already the tenant by the time this is seen.
		chk("mid-frame, ATT is asserted", !att0_n || !att1_n);
		enable = 0;
		@(posedge clk);
		@(posedge clk);
		chk("disable mid-frame releases the bus at once", bus_idle);

		// It must also STAY released: a state machine that resumes where it
		// left off would re-assert ATT a few cycles later.
		saw_activity = 0;
		for (n = 0; n < 200000; n = n + 1) begin
			@(posedge clk);
			if (!bus_idle) saw_activity = 1;
		end
		chk("and stays released", !saw_activity);

		// ---- 4. re-enable: the reader comes back ---------------------------
		// A tenant that cannot be handed the port back is no better than one
		// that never gives it up.
		enable = 1;
		wait_active(started);
		chk("re-enabled, reader starts again", started);

		// ---- 5. results are cleared while disabled -------------------------
		// A held button must not survive the switch away: the OSD reads these
		// registers regardless of who owns the port, so a latched pad0 would
		// keep pressing a menu key with the pads not even connected.
		//
		// The pad is holding X with its sticks off centre, so wait for the reader
		// to actually see both -- checking that they are back to default after a
		// disable proves nothing unless they were not default before.
		started = 0;
		for (n = 0; n < 4000000 && !started; n = n + 1) begin
			@(posedge clk);
			if (pad0 != 16'h0000 && axes0 != 32'h80808080) started = 1;
		end
		chk("pad0 and axes0 read the pad before the switch", started);

		enable = 0;
		repeat (10) @(posedge clk);
		chk("disabled clears id0/id1",   id0 == 8'h00 && id1 == 8'h00);
		chk("disabled clears pad0/pad1", pad0 == 16'h0000 && pad1 == 16'h0000);
		chk("disabled centres axes",     axes0 == 32'h80808080 && axes1 == 32'h80808080);

		if (errors == 0) $display("RUN: PASS (CLK_KHZ=%0d)", CLK_KHZ);
		else             $display("RUN: FAIL (%0d errors, CLK_KHZ=%0d)", errors, CLK_KHZ);
		$finish;
	end

	initial begin
		#200000000;
		$display("FAIL: timeout");
		$display("RUN: FAIL (timeout)");
		$finish;
	end

endmodule
