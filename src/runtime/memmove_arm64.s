// Copyright 2026 Google LLC
// Author: edwinchiu
// Assisted-By: Gemini 3 Pro Preview

#include "textflag.h"

// See memmove Go doc for important implementation constraints.

// Register map
//
// dstin  R0
// src    R1
// count  R2
// dst    R3 (same as R0, but gets modified in unaligned cases)
// srcend R4
// dstend R5
// data   R6-R17
// tmp1   R14

// func memmove(to, from unsafe.Pointer, n uintptr)
TEXT runtime·memmove<ABIInternal>(SB), NOSPLIT|NOFRAME, $0-24
	CBZ	R2, copy0

	// Feature Check Dispatch using R16 (temp)
	MOVBU	runtime·arm64UseMOPS(SB), R16
	CBNZ	R16, copy_mops

	// Overlap Check
	// If dst < src (bit 63 set), it is always safe for forward copy.
	// If dst >= src, we must check if they overlap (dist < n).
	SUB	R1, R0, R16
	TBNZ	$63, R16, forward_path // dst < src: safe
	CMP	R2, R16
	BHI	standard_path          // Overlap: use Standard backward

forward_path:
	MOVBU	runtime·arm64UseSVEAlways(SB), R16
	CBNZ	R16, copy_sve

	MOVBU	runtime·arm64UseNEON(SB), R16
	CBZ	R16, check_sve
	CMP	$256, R2
	BHS	copy_neon

check_sve:
	MOVBU	runtime·arm64UseSVE(SB), R16
	CBZ	R16, standard_path
	CMP	$0x100000, R2
	BHS	copy_sve_big
	B	standard_path

standard_path:
	// Small copies: 1..16 bytes
	CMP	$16, R2
	BLE	copy16

	// Large copies
	CMP	$128, R2
	BHI	copy_long

	CMP	$32, R2
	BHI	copy32_128

	// Small copies: 17..32 bytes.
	LDP	(R1), (R6, R7)
	ADD	R1, R2, R4          // R4 points just past the last source byte
	LDP	-16(R4), (R12, R13)
	STP	(R6, R7), (R0)
	ADD	R0, R2, R5          // R5 points just past the last destination byte
	STP	(R12, R13), -16(R5)
	RET

// Small copies: 1..16 bytes.
copy16:
	ADD	R1, R2, R4 // R4 points just past the last source byte
	ADD	R0, R2, R5 // R5 points just past the last destination byte
	CMP	$8, R2
	BLT	copy7
	MOVD	(R1), R6
	MOVD	-8(R4), R7
	MOVD	R6, (R0)
	MOVD	R7, -8(R5)
	RET

copy7:
	TBZ	$2, R2, copy3
	MOVWU	(R1), R6
	MOVWU	-4(R4), R7
	MOVW	R6, (R0)
	MOVW	R7, -4(R5)
	RET

copy3:
	TBZ	$1, R2, copy1
	MOVHU	(R1), R6
	MOVHU	-2(R4), R7
	MOVH	R6, (R0)
	MOVH	R7, -2(R5)
	RET

copy1:
	MOVBU	(R1), R6
	MOVB	R6, (R0)

copy0:
	RET

	// Medium copies: 33..128 bytes.
copy32_128:
	ADD	R1, R2, R4          // R4 points just past the last source byte
	ADD	R0, R2, R5          // R5 points just past the last destination byte
	LDP	(R1), (R6, R7)
	LDP	16(R1), (R8, R9)
	LDP	-32(R4), (R10, R11)
	LDP	-16(R4), (R12, R13)
	CMP	$64, R2
	BHI	copy128
	STP	(R6, R7), (R0)
	STP	(R8, R9), 16(R0)
	STP	(R10, R11), -32(R5)
	STP	(R12, R13), -16(R5)
	RET

	// Copy 65..128 bytes.
copy128:
	LDP	32(R1), (R14, R15)
	LDP	48(R1), (R16, R17)
	CMP	$96, R2
	BLS	copy96
	LDP	-64(R4), (R2, R3)
	LDP	-48(R4), (R1, R4)
	STP	(R2, R3), -64(R5)
	STP	(R1, R4), -48(R5)

copy96:
	STP	(R6, R7), (R0)
	STP	(R8, R9), 16(R0)
	STP	(R14, R15), 32(R0)
	STP	(R16, R17), 48(R0)
	STP	(R10, R11), -32(R5)
	STP	(R12, R13), -16(R5)
	RET

	// Copy more than 128 bytes.
copy_long:
	ADD	R1, R2, R4 // R4 points just past the last source byte
	ADD	R0, R2, R5 // R5 points just past the last destination byte
	MOVD	ZR, R7
	MOVD	ZR, R8

	CMP	$1024, R2
	BLT	backward_check
	// feature detect to decide how to align
	MOVBU	runtime·arm64UseAlignedLoads(SB), R6
	CBNZ	R6, use_aligned_loads
	MOVD	R0, R7
	MOVD	R5, R8
	B	backward_check
use_aligned_loads:
	MOVD	R1, R7
	MOVD	R4, R8
	// R7 and R8 are used here for the realignment calculation. In
	// the use_aligned_loads case, R7 is the src pointer and R8 is
	// srcend pointer, which is used in the backward copy case.
	// When doing aligned stores, R7 is the dst pointer and R8 is
	// the dstend pointer.

backward_check:
	// Use backward copy if there is an overlap.
	SUB	R1, R0, R14
	CBZ	R14, copy0
	CMP	R2, R14
	BCC	copy_long_backward

	// Copy 16 bytes and then align src (R1) or dst (R0) to 16-byte alignment.
	LDP	(R1), (R12, R13)     // Load  A
	AND	$15, R7, R14         // Calculate the realignment offset
	SUB	R14, R1, R1
	SUB	R14, R0, R3          // move dst back same amount as src
	ADD	R14, R2, R2
	LDP	16(R1), (R6, R7)     // Load   B
	STP	(R12, R13), (R0)     // Store A
	LDP	32(R1), (R8, R9)     // Load    C
	LDP	48(R1), (R10, R11)   // Load     D
	LDP.W	64(R1), (R12, R13)   // Load      E
	// 80 bytes have been loaded; if less than 80+64 bytes remain, copy from the end
	SUBS	$144, R2, R2
	BLS	copy64_from_end

loop64:
	STP	(R6, R7), 16(R3)     // Store  B
	LDP	16(R1), (R6, R7)     // Load   B (next iteration)
	STP	(R8, R9), 32(R3)     // Store   C
	LDP	32(R1), (R8, R9)     // Load    C
	STP	(R10, R11), 48(R3)   // Store    D
	LDP	48(R1), (R10, R11)   // Load     D
	STP.W	(R12, R13), 64(R3)   // Store     E
	LDP.W	64(R1), (R12, R13)   // Load      E
	SUBS	$64, R2, R2
	BHI	loop64

	// Write the last iteration and copy 64 bytes from the end.
copy64_from_end:
	LDP	-64(R4), (R14, R15)  // Load       F
	STP	(R6, R7), 16(R3)     // Store  B
	LDP	-48(R4), (R6, R7)    // Load        G
	STP	(R8, R9), 32(R3)     // Store   C
	LDP	-32(R4), (R8, R9)    // Load         H
	STP	(R10, R11), 48(R3)   // Store    D
	LDP	-16(R4), (R10, R11)  // Load          I
	STP	(R12, R13), 64(R3)   // Store     E
	STP	(R14, R15), -64(R5)  // Store      F
	STP	(R6, R7), -48(R5)    // Store       G
	STP	(R8, R9), -32(R5)    // Store        H
	STP	(R10, R11), -16(R5)  // Store         I
	RET

	// Large backward copy for overlapping copies.
	// Copy 16 bytes and then align srcend (R4) or dstend (R5) to 16-byte alignment.
copy_long_backward:
	LDP	-16(R4), (R12, R13)
	AND	$15, R8, R14
	SUB	R14, R4, R4
	SUB	R14, R2, R2
	LDP	-16(R4), (R6, R7)
	STP	(R12, R13), -16(R5)
	LDP	-32(R4), (R8, R9)
	LDP	-48(R4), (R10, R11)
	LDP.W	-64(R4), (R12, R13)
	SUB	R14, R5, R5
	SUBS	$128, R2, R2
	BLS	copy64_from_start

loop64_backward:
	STP	(R6, R7), -16(R5)
	LDP	-16(R4), (R6, R7)
	STP	(R8, R9), -32(R5)
	LDP	-32(R4), (R8, R9)
	STP	(R10, R11), -48(R5)
	LDP	-48(R4), (R10, R11)
	STP.W	(R12, R13), -64(R5)
	LDP.W	-64(R4), (R12, R13)
	SUBS	$64, R2, R2
	BHI	loop64_backward

	// Write the last iteration and copy 64 bytes from the start.
copy64_from_start:
	LDP	48(R1), (R2, R3)
	STP	(R6, R7), -16(R5)
	LDP	32(R1), (R6, R7)
	STP	(R8, R9), -32(R5)
	LDP	16(R1), (R8, R9)
	STP	(R10, R11), -48(R5)
	LDP	(R1), (R10, R11)
	STP	(R12, R13), -64(R5)
	STP	(R2, R3), 48(R0)
	STP	(R6, R7), 32(R0)
	STP	(R8, R9), 16(R0)
	STP	(R10, R11), (R0)
	RET

copy_mops:
	// CPYFP [X0]!, [X1]!, X2!  => 0x19010420
	WORD	$0x19010420
	// CPYFM [X0]!, [X1]!, X2!  => 0x19014420
	WORD	$0x19014420
	// CPYFE [X0]!, [X1]!, X2!  => 0x19018420
	WORD	$0x19018420
	RET

copy_neon:
	// R0=dst, R1=src, R2=n
neon_loop:
	VLD1.P	64(R1), [V0.B16, V1.B16, V2.B16, V3.B16]
	VST1.P	[V0.B16, V1.B16, V2.B16, V3.B16], 64(R0)
	SUB	$64, R2
	CMP	$64, R2
	BHS	neon_loop
	
	// Jump to standard path for remainder
	CBZ	R2, copy0
	B	standard_path

// SVE implementation
copy_sve:
	// Forward copy
	CMP	$0x100000, R2
	BHS	copy_sve_big

copy_sve_loop_entry:
	WORD	$0x0420e3e3	// CNTB	R3
	CMP	$16, R2
	BLO	loop_sve_1x

	// Align R0 to 16 bytes
	NEG	R0, R14
	AND	$15, R14, R14
	CBZ	R14, copy_sve_forward
	WORD	$0x252e17e0	// WHILELT	P0.B, ZR, R14
	WORD	$0xa400a020	// LD1B	(R1), P0/Z, Z0.B
	WORD	$0xe400e000	// ST1B	Z0.B, P0, (R0)
	ADD	R14, R1
	ADD	R14, R0
	SUB	R14, R2

copy_sve_forward:
	ADD	R3, R3, R5	// 2*VL
	ADD	R3, R5, R6	// 3*VL
	ADD	R5, R5, R7	// 4*VL

loop_sve_4x:
	CMP	R7, R2
	BLO	loop_sve_1x
	WORD	$0x252217e0	// WHILELT	P0.B, ZR, R2
	WORD	$0x25221461	// WHILELT	P1.B, R3, R2
	WORD	$0x252214a2	// WHILELT	P2.B, R5, R2
	WORD	$0x252214c3	// WHILELT	P3.B, R6, R2

	WORD	$0xa400a020	// LD1B	(R1), P0/Z, Z0.B
	WORD	$0xa401a421	// LD1B	(R1), P1/Z, Z1.B
	WORD	$0xa402a822	// LD1B	(R1), P2/Z, Z2.B
	WORD	$0xa403ac23	// LD1B	(R1), P3/Z, Z3.B

	WORD	$0xe400e000	// ST1B	Z0.B, P0, (R0)
	WORD	$0xe401e401	// ST1B	Z1.B, P1, (R0)
	WORD	$0xe402e802	// ST1B	Z2.B, P2, (R0)
	WORD	$0xe403ec03	// ST1B	Z3.B, P3, (R0)

	WORD	$0x0433e3e1	// INCB	R1, ALL, MUL #4
	WORD	$0x0433e3e0	// INCB	R0, ALL, MUL #4
	SUB	R7, R2
	B	loop_sve_4x

loop_sve_1x:
	CMP	$0, R2
	BLE	copy_sve_done
loop_sve_1x_inner:
	WORD	$0x252217e0	// WHILELT	P0.B, ZR, R2
	WORD	$0xa400a020	// LD1B	(R1), P0/Z, Z0.B
	WORD	$0xe400e000	// ST1B	Z0.B, P0, (R0)
	WORD	$0x0430e3e1	// INCB	R1
	WORD	$0x0430e3e0	// INCB	R0
	SUB	R3, R2
	CMP	$0, R2
	BGT	loop_sve_1x_inner

copy_sve_done:
	RET

copy_sve_big:
	WORD	$0x0420e3e3	// CNTB	R3
	ADD	R3, R3, R5	// 2*VL
	ADD	R3, R5, R6	// 3*VL
	ADD	R5, R5, R7	// 4*VL
	WORD	$0x2518e3e0	// PTRUE	P0.B

loop_sve_big:
	CMP	R7, R2
	BLO	copy_sve_loop_entry
	// Prefetch
	WORD	$0x85c40021
	WORD	$0x85c50021
	WORD	$0x85c60021
	WORD	$0x85c70021

	// LDNT1B
	WORD	$0xa400e020
	WORD	$0xa401e021
	WORD	$0xa402e022
	WORD	$0xa403e023

	// STNT1B
	WORD	$0xe410e000
	WORD	$0xe411e001
	WORD	$0xe412e002
	WORD	$0xe413e003

	WORD	$0x0433e3e1	// INCB	R1, ALL, MUL #4
	WORD	$0x0433e3e0	// INCB	R0, ALL, MUL #4
	SUB	R7, R2
	B	loop_sve_big
