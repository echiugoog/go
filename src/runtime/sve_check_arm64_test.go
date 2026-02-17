// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build arm64

package runtime_test

import (
	"runtime"
	"testing"
)

func TestCheckSVE(t *testing.T) {
	t.Logf("arm64UseSVE: %v", *runtime.Arm64UseSVE)
	t.Logf("arm64UseMOPS: %v", *runtime.Arm64UseMOPS)
}
