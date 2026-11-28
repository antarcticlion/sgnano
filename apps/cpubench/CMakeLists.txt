# cpubench: sgnano の CPU の計測（Dhrystone 2.1 と Linpack を、画面モードと音楽の負荷の下で測る外部実行ファイル cpubench.sgx）。
#
#   cmake -S apps/cpubench -B build/cpubench -G Ninja -DCMAKE_TOOLCHAIN_FILE=apps/cpubench/cmake/arm-none-eabi.cmake
#   cmake --build build/cpubench
#   できるもの: build/cpubench/sgx/cpubench.sgx（S: か USB のドライブの同じフォルダに skyward_pulse.vgz / .mp3 を置く）
#
# SDK はこのリポジトリの sdk/sgx（別の置き場は -DSGNANO_SGX_SDK_DIR=）。arm-none-eabi-gcc（10.3.1 で確かめた）と Python 3 が要る。
cmake_minimum_required(VERSION 3.21)
project(sgnano_cpubench LANGUAGES C ASM)

set(SGNANO_SGX_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/sgx" CACHE PATH "sgnano SGX SDK directory")
if(NOT EXISTS "${SGNANO_SGX_SDK_DIR}/sgx.cmake")
    message(FATAL_ERROR "SGNANO_SGX_SDK_DIR does not contain sgx.cmake: ${SGNANO_SGX_SDK_DIR}")
endif()
include("${SGNANO_SGX_SDK_DIR}/sgx.cmake")

# 計算の本体は third_party の元の版をそのまま組む（Dhrystone は K&R の書き方なので -std=gnu89、main などをつなぎへ名前を替える）。
# FLAGS 17 = SGX_F_ESC_KEY | SGX_F_LOCALIZE
set(_d ${CMAKE_CURRENT_SOURCE_DIR})
sgx_add_program(cpubench NAME "CPU BENCH" FLAGS 17
    SOURCES ${_d}/cpubench.c ${_d}/bench_dhry.c ${_d}/lp_sp.c ${_d}/lp_dp.c
            ${_d}/third_party/dhrystone/dhry_1.c ${_d}/third_party/dhrystone/dhry_2.c
            ${_d}/dhry0_1.c ${_d}/dhry0_2.c)
set_source_files_properties(${_d}/third_party/dhrystone/dhry_1.c ${_d}/third_party/dhrystone/dhry_2.c PROPERTIES COMPILE_OPTIONS
    "-std=gnu89;-w;-DTIME;-Dmain=dhry_main;-Dscanf=dhry_scanf;-Dprintf=dhry_printf;-Dmalloc=dhry_malloc;-Dtime=dhry_time;-include;${_d}/dhry_shim.h")
# Core 0 で 2 本目を走らせる Dhrystone（2026-11-24、SGX ABI 5.19。元の版を別の名前で取り込む: dhry0_shim.h）
set_source_files_properties(${_d}/dhry0_1.c ${_d}/dhry0_2.c PROPERTIES COMPILE_OPTIONS "-std=gnu89;-w;-DTIME;-I${_d}/third_party/dhrystone")
set_source_files_properties(${_d}/lp_sp.c ${_d}/lp_dp.c PROPERTIES COMPILE_OPTIONS "-w")
