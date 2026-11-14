; RUN: if [ %llvmver -ge 15 ]; then %opt < %s %OPnewLoadEnzyme -enzyme-preopt=false -passes="enzyme" -S | FileCheck %s; fi

; Julia attaches bundles to its allocations that tell its GC lowering to zero
; their GC pointers. The shadow allocation must carry them too, and since Julia
; then zeroes those bytes, Enzyme only zeroes the rest of the shadow.

declare noalias nonnull ptr addrspace(10) @julia.gc_alloc_obj(ptr, i64, ptr addrspace(10))

declare ptr @julia.get_pgcstack()

; A double at 0 and a GC pointer at 8.
define double @ptrs(double %x) {
top:
  %pgcstack = call ptr @julia.get_pgcstack()
  %obj = call noalias nonnull align 8 dereferenceable(16) ptr addrspace(10) @julia.gc_alloc_obj(ptr %pgcstack, i64 16, ptr addrspace(10) addrspacecast (ptr inttoptr (i64 1234 to ptr) to ptr addrspace(10))) [ "julia.gc_alloc_ptr_offsets"(i64 8) ]
  %fld = addrspacecast ptr addrspace(10) %obj to ptr addrspace(11)
  store double %x, ptr addrspace(11) %fld, align 8
  %ld = load double, ptr addrspace(11) %fld, align 8
  %m = fmul double %ld, %ld
  ret double %m
}

; GC pointers at 0 and 16, doubles at 8 and 24.
define double @twoptrs(double %x) {
top:
  %pgcstack = call ptr @julia.get_pgcstack()
  %obj = call noalias nonnull align 8 dereferenceable(32) ptr addrspace(10) @julia.gc_alloc_obj(ptr %pgcstack, i64 32, ptr addrspace(10) addrspacecast (ptr inttoptr (i64 1234 to ptr) to ptr addrspace(10))) [ "julia.gc_alloc_ptr_offsets"(i64 16, i64 0) ]
  %obj11 = addrspacecast ptr addrspace(10) %obj to ptr addrspace(11)
  %fld = getelementptr inbounds i8, ptr addrspace(11) %obj11, i64 24
  store double %x, ptr addrspace(11) %fld, align 8
  %ld = load double, ptr addrspace(11) %fld, align 8
  %m = fmul double %ld, %ld
  ret double %m
}

; A double at 0 and a region of GC pointers after it.
define double @region(double %x) {
top:
  %pgcstack = call ptr @julia.get_pgcstack()
  %obj = call noalias nonnull align 8 dereferenceable(16) ptr addrspace(10) @julia.gc_alloc_obj(ptr %pgcstack, i64 16, ptr addrspace(10) addrspacecast (ptr inttoptr (i64 1234 to ptr) to ptr addrspace(10))) [ "julia.gc_alloc_zeroinit"(i64 8, i64 8) ]
  %fld = addrspacecast ptr addrspace(10) %obj to ptr addrspace(11)
  store double %x, ptr addrspace(11) %fld, align 8
  %ld = load double, ptr addrspace(11) %fld, align 8
  %m = fmul double %ld, %ld
  ret double %m
}

; A region whose size is only known at run time.
define double @dynregion(double %x, i64 %n) {
top:
  %pgcstack = call ptr @julia.get_pgcstack()
  %tot = add i64 %n, 16
  %obj = call noalias nonnull align 8 ptr addrspace(10) @julia.gc_alloc_obj(ptr %pgcstack, i64 %tot, ptr addrspace(10) addrspacecast (ptr inttoptr (i64 1234 to ptr) to ptr addrspace(10))) [ "julia.gc_alloc_zeroinit"(i64 16, i64 %n) ]
  %fld = addrspacecast ptr addrspace(10) %obj to ptr addrspace(11)
  store double %x, ptr addrspace(11) %fld, align 8
  %ld = load double, ptr addrspace(11) %fld, align 8
  %m = fmul double %ld, %ld
  ret double %m
}

declare double @__enzyme_autodiff(...)

define double @dptrs(double %x) {
entry:
  %r = call double (...) @__enzyme_autodiff(ptr @ptrs, double %x)
  ret double %r
}

define double @dtwoptrs(double %x) {
entry:
  %r = call double (...) @__enzyme_autodiff(ptr @twoptrs, double %x)
  ret double %r
}

define double @dregion(double %x) {
entry:
  %r = call double (...) @__enzyme_autodiff(ptr @region, double %x)
  ret double %r
}

define double @ddynregion(double %x, i64 %n) {
entry:
  %r = call double (...) @__enzyme_autodiff(ptr @dynregion, double %x, i64 %n)
  ret double %r
}

; CHECK-LABEL: define internal { double } @diffeptrs(
; CHECK: %"obj'mi" = call {{.*}}@julia.gc_alloc_obj(ptr %pgcstack, i64 16, {{.*}}) {{.*}}[ "julia.gc_alloc_ptr_offsets"(i64 8) ]
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %"obj'mi", i8 0, i64 8, i1 false)
; CHECK-NEXT: %obj = call {{.*}}@julia.gc_alloc_obj(ptr %pgcstack, i64 16, {{.*}}) {{.*}}[ "julia.gc_alloc_ptr_offsets"(i64 8) ]

; CHECK-LABEL: define internal { double } @diffetwoptrs(
; CHECK: %"obj'mi" = call {{.*}}@julia.gc_alloc_obj(ptr %pgcstack, i64 32, {{.*}}) {{.*}}[ "julia.gc_alloc_ptr_offsets"(i64 16, i64 0) ]
; CHECK-NEXT: %[[lo:.+]] = getelementptr inbounds i8, ptr addrspace(10) %"obj'mi", i64 8
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %[[lo]], i8 0, i64 8, i1 false)
; CHECK-NEXT: %[[hi:.+]] = getelementptr inbounds i8, ptr addrspace(10) %"obj'mi", i64 24
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %[[hi]], i8 0, i64 8, i1 false)
; CHECK-NEXT: %obj = call

; CHECK-LABEL: define internal { double } @differegion(
; CHECK: %"obj'mi" = call {{.*}}@julia.gc_alloc_obj(ptr %pgcstack, i64 16, {{.*}}) {{.*}}[ "julia.gc_alloc_zeroinit"(i64 8, i64 8) ]
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %"obj'mi", i8 0, i64 8, i1 false)
; CHECK-NEXT: %obj = call

; CHECK-LABEL: define internal { double } @diffedynregion(
; CHECK: %"obj'mi" = call {{.*}}@julia.gc_alloc_obj(ptr %pgcstack, i64 %tot, {{.*}}) {{.*}}[ "julia.gc_alloc_zeroinit"(i64 16, i64 %n) ]
; CHECK-NEXT: %[[end:.+]] = add i64 16, %n
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %"obj'mi", i8 0, i64 16, i1 false)
; CHECK-NEXT: %[[tail:.+]] = getelementptr inbounds i8, ptr addrspace(10) %"obj'mi", i64 %[[end]]
; CHECK-NEXT: %[[len:.+]] = sub i64 %tot, %[[end]]
; CHECK-NEXT: call void @llvm.memset.p10.i64(ptr addrspace(10) nonnull %[[tail]], i8 0, i64 %[[len]], i1 false)
; CHECK-NEXT: %obj = call
