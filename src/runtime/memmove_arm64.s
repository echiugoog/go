// Copyright 2014 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

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

// Copies are split into 3 main cases: small copies of up to 32 bytes, medium
// copies of up to 128 bytes, and large copies. The overhead of the overlap
// check is negligible since it is only required for large copies.
//
// Large copies use a software pipelined loop processing 64 bytes per iteration.
// The destination pointer is 16-byte aligned to minimize unaligned accesses.
// The loop tail is handled by always copying 64 bytes from the end.

// func memmove(to, from unsafe.Pointer, n uintptr)
TEXT runtime·memmove<ABIInternal>(SB), NOSPLIT|NOFRAME, $0-24
	CBZ	R2, copy0

	MOVBU	runtime·arm64UseNEON(SB), R14
	CBNZ	R14, memmove_neon

	MOVBU	runtime·arm64UseSVE(SB), R14
	CBNZ	R14, memmove_sve

memmove_base:
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

// ============================================================================
// Dedicated NEON Implementation (memmove_neon)
// ============================================================================
memmove_neon:
	ADD	R1, R2, R4          // R4 = srcend
	ADD	R0, R2, R5          // R5 = dstend

	// Small copies: 1..16 bytes use general integer routine for low latency
	CMP	$16, R2
	BLE	copy16

	// Check if > 128 bytes (long copy)
	CMP	$128, R2
	BHI	neon_long

	// Check if <= 32 bytes (17..32 bytes)
	CMP	$32, R2
	BHI	neon_33_128
	FMOVQ	(R1), F0
	FMOVQ	-16(R4), F1
	FMOVQ	F0, (R0)
	FMOVQ	F1, -16(R5)
	RET

neon_33_128:
	// Copy 33..128 bytes using 128-bit vector pairs (32 bytes per instruction)
	CMP	$64, R2
	BHI	neon_65_128
	FLDPQ	(R1), (F0, F1)
	FLDPQ	-32(R4), (F2, F3)
	FSTPQ	(F0, F1), (R0)
	FSTPQ	(F2, F3), -32(R5)
	RET

neon_65_128:
	FLDPQ	(R1), (F0, F1)
	FLDPQ	32(R1), (F2, F3)
	FLDPQ	-64(R4), (F4, F5)
	FLDPQ	-32(R4), (F6, F7)
	FSTPQ	(F0, F1), (R0)
	FSTPQ	(F2, F3), 32(R0)
	FSTPQ	(F4, F5), -64(R5)
	FSTPQ	(F6, F7), -32(R5)
	RET

neon_long:
	// Check for overlap requiring backward copy
	SUB	R1, R0, R14
	CBZ	R14, neon_copy0
	CMP	R2, R14
	BCC	neon_long_backward

	// Forward copies over 128 bytes: loop processing 64 bytes per iteration
	MOVD	R0, R3
	MOVD	R1, R6
neon_loop64:
	VLD1.P	64(R6), [V0.B16, V1.B16, V2.B16, V3.B16]
	VST1.P	[V0.B16, V1.B16, V2.B16, V3.B16], 64(R3)
	SUBS	$64, R2, R2
	CBZ	R2, neon_copy0
	CMP	$64, R2
	BHS	neon_loop64

	// Process remaining uncopied tail (< 64 bytes) starting cleanly from current positions R6/R3
neon_tail:
	MOVD	R6, R1
	MOVD	R3, R0
	ADD	R1, R2, R4
	ADD	R0, R2, R5
	CMP	$32, R2
	BHI	neon_33_128
	CMP	$16, R2
	BLE	copy16
	// Inlined 17..32-byte copy (keep synchronized with memmove_neon:265)
	FMOVQ	(R1), F0
	FMOVQ	-16(R4), F1
	FMOVQ	F0, (R0)
	FMOVQ	F1, -16(R5)
	RET

neon_copy0:
	RET

neon_long_backward:
	// Overlapping backward copy (R0 > R1 and R0 - R1 < n)
	MOVD	R4, R6
	MOVD	R5, R3
neon_loop64_backward:
	CMP	$128, R2
	BLS	neon_backward_tail
	SUB	$64, R6, R6
	SUB	$64, R3, R3
	VLD1	(R6), [V0.B16, V1.B16, V2.B16, V3.B16]
	VST1	[V0.B16, V1.B16, V2.B16, V3.B16], (R3)
	SUB	$64, R2, R2
	B	neon_loop64_backward

neon_backward_tail:
	// Recalculate srcend and dstend for exact uncopied start slice (<= 128 bytes)
	ADD	R1, R2, R4
	ADD	R0, R2, R5
	CMP	$32, R2
	BHI	neon_33_128
	CMP	$16, R2
	BLE	copy16
	// Inlined 17..32-byte copy (keep synchronized with memmove_neon:265)
	FMOVQ	(R1), F0
	FMOVQ	-16(R4), F1
	FMOVQ	F0, (R0)
	FMOVQ	F1, -16(R5)
	RET

// ============================================================================
// Dedicated SVE / SVE2 Implementation (memmove_sve)
// ============================================================================
memmove_sve:
	ADD	R1, R2, R4          // R4 = srcend
	ADD	R0, R2, R5          // R5 = dstend
	RDVL	$1, R14             // R14 = VL in bytes (e.g., 16, 32, 64)
	MOVD	ZR, R11             // R11 = 0 (used for index addressing and predicates)

	CMP	$128, R2
	BHI	sve_long

sve_medium_dispatch:
	// Check small/medium copies (<= 128 bytes)
	CMP	R14, R2
	BLS	sve_le_vl

	// If count <= 2 * VL (e.g. up to 32 bytes for VL=16), copy via 2 overlapping vectors
	ADD	R14, R14, R8        // R8 = 2 * VL
	CMP	R8, R2
	BLS	sve_le_2vl

	// Copy up to 128 bytes across multiple vectors
	CMP	$64, R2
	BHI	sve_65_128
	PWHILELO	R14, R11, P0.B

	// 33..64 bytes (covers up to 4*VL when VL=16)
	SUB	R8, R4, R6          // R6 = srcend - 2*VL
	SUB	R8, R5, R7          // R7 = dstend - 2*VL
	ZLD1B	(R1)(R11), P0.Z, [Z0.B]
	ZLD1B	(R1)(R14), P0.Z, [Z1.B]
	ZLD1B	(R6)(R11), P0.Z, [Z2.B]
	ZLD1B	(R6)(R14), P0.Z, [Z3.B]
	ZST1B	[Z0.B], P0, (R0)(R11)
	ZST1B	[Z1.B], P0, (R0)(R14)
	ZST1B	[Z2.B], P0, (R7)(R11)
	ZST1B	[Z3.B], P0, (R7)(R14)
	RET

sve_le_vl:
	PWHILELO	R2, R11, P0.B
	ZLD1B	(R1)(R11), P0.Z, [Z0.B]
	ZST1B	[Z0.B], P0, (R0)(R11)
	RET

sve_le_2vl:
	PWHILELO	R14, R11, P0.B
	SUB	R14, R4, R6         // R6 = srcend - VL
	SUB	R14, R5, R7         // R7 = dstend - VL
	ZLD1B	(R1)(R11), P0.Z, [Z0.B]
	ZLD1B	(R6)(R11), P0.Z, [Z1.B]
	ZST1B	[Z0.B], P0, (R0)(R11)
	ZST1B	[Z1.B], P0, (R7)(R11)
	RET

sve_65_128:
	FLDPQ	(R1), (F0, F1)
	FLDPQ	32(R1), (F2, F3)
	FLDPQ	-64(R4), (F4, F5)
	FLDPQ	-32(R4), (F6, F7)
	FSTPQ	(F0, F1), (R0)
	FSTPQ	(F2, F3), 32(R0)
	FSTPQ	(F4, F5), -64(R5)
	FSTPQ	(F6, F7), -32(R5)
	RET

sve_long:
	SUB	R1, R0, R12
	CBZ	R12, sve_copy0
	CMP	R2, R12
	BCC	sve_long_backward

	// Forward SVE loop: process 4 * VL bytes per iteration
	ADD	R14, R14, R8        // R8 = 2 * VL
	ADD	R8, R14, R9         // R9 = 3 * VL
	ADD	R8, R8, R15         // R15 = 4 * VL
	MOVD	R1, R6              // current src pointer
	MOVD	R0, R7              // current dst pointer
	PWHILELO	R14, R11, P0.B

sve_loop_long:
	CBZ	R2, sve_copy0
	CMP	R15, R2
	BLO	sve_long_tail
	ZLD1B	(R6)(R11), P0.Z, [Z0.B]
	ZLD1B	(R6)(R14), P0.Z, [Z1.B]
	ZLD1B	(R6)(R8), P0.Z, [Z2.B]
	ZLD1B	(R6)(R9), P0.Z, [Z3.B]
	ZST1B	[Z0.B], P0, (R7)(R11)
	ZST1B	[Z1.B], P0, (R7)(R14)
	ZST1B	[Z2.B], P0, (R7)(R8)
	ZST1B	[Z3.B], P0, (R7)(R9)
	ADD	R15, R6
	ADD	R15, R7
	SUB	R15, R2
	JMP	sve_loop_long

sve_long_tail:
	// Handle remaining forward tail (< 4*VL bytes) directly right from active pointer positions R6/R7
	MOVD	R6, R1
	MOVD	R7, R0
	ADD	R1, R2, R4
	ADD	R0, R2, R5
	B	sve_medium_dispatch
sve_copy0:
	RET

sve_long_backward:
	// Backward SVE loop: reserve the start slice right away and loop down from srcend
	ADD	R14, R14, R8        // R8 = 2 * VL
	ADD	R8, R14, R9         // R9 = 3 * VL
	ADD	R8, R8, R15         // R15 = 4 * VL
	MOVD	R4, R6              // current src pointer (start at srcend)
	MOVD	R5, R7              // current dst pointer (start at dstend)
	PWHILELO	R14, R11, P0.B

sve_loop_backward:
	CMP	$128, R2
	BLS	sve_backward_tail
	SUB	R15, R6
	SUB	R15, R7
	ZLD1B	(R6)(R11), P0.Z, [Z0.B]
	ZLD1B	(R6)(R14), P0.Z, [Z1.B]
	ZLD1B	(R6)(R8), P0.Z, [Z2.B]
	ZLD1B	(R6)(R9), P0.Z, [Z3.B]
	ZST1B	[Z0.B], P0, (R7)(R11)
	ZST1B	[Z1.B], P0, (R7)(R14)
	ZST1B	[Z2.B], P0, (R7)(R8)
	ZST1B	[Z3.B], P0, (R7)(R9)
	SUB	R15, R2
	JMP	sve_loop_backward

sve_backward_tail:
	// Recalculate srcend and dstend and copy remaining uncorrupted start slice across medium dispatch
	ADD	R1, R2, R4
	ADD	R0, R2, R5
	B	sve_medium_dispatch
