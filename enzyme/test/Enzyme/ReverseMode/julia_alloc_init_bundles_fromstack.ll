; RUN: if [ %llvmver -ge 15 ]; then %opt < %s %OPnewLoadEnzyme -enzyme-preopt=false -passes="enzyme" -S | FileCheck %s; fi

; The shadow of an allocation that came from the stack (`enzyme_fromstack`) is
; moved back there, which drops the bundles that have Julia's GC lowering zero
; part of it. Enzyme must then zero all of the shadow itself.

declare noalias nonnull ptr addrspace(10) @julia.gc_alloc_obj(ptr, i64, ptr addrspace(10))

declare double @__enzyme_autodiff(...)

define double @f(double %x) {
entry:
  %al = call noalias nonnull dereferenceable(16) ptr addrspace(10) @julia.gc_alloc_obj(ptr null, i64 16, ptr addrspace(10) addrspacecast (ptr inttoptr (i64 1234 to ptr) to ptr addrspace(10))) [ "julia.gc_alloc_ptr_offsets"(i64 8) ], !enzyme_fromstack !0
  %ald = addrspacecast ptr addrspace(10) %al to ptr addrspace(11)
  store double %x, ptr addrspace(11) %ald, align 8
  %v = load double, ptr addrspace(11) %ald, align 8
  %sq = fmul double %v, %v
  ret double %sq
}

define double @df(double %x) {
entry:
  %r = call double (...) @__enzyme_autodiff(ptr @f, double %x)
  ret double %r
}

!0 = !{i64 16}

; CHECK-LABEL: define internal { double } @diffef(
; CHECK: %"al'mi" = alloca i8, i64 16
; CHECK-NEXT: call void @llvm.memset.p0.i64(ptr nonnull dereferenceable(16) dereferenceable_or_null(16) %"al'mi", i8 0, i64 16, i1 false)
