@echo off
REM ============================================================
REM run_sim.bat — Simulate rm_bitcoin and rm_kaspa RMs in ModelSim
REM Output saved to simulation\
REM ============================================================

set MODELSIM_PATH=D:\Applications\modelsim_ase\win32aloem
set RTL_DIR=D:\Projects\Crypto_miner_final_updated_on_18_06\New_updated\pdsa_updated_on_3_6_newv\rtl
set SCRIPT_DIR=D:\Projects\Crypto_miner_final_updated_on_18_06\New_updated\pdsa_updated_on_3_6_newv\simulation
set OUTPUT_DIR=D:\Projects\Crypto_miner_final_updated_on_18_06\New_updated\pdsa_updated_on_3_6_newv\simulation

echo ============================================================
echo PDSA-FPGA RM Simulation
echo ============================================================

REM Clean old outputs
if exist "%OUTPUT_DIR%\work_btc" rmdir /s /q "%OUTPUT_DIR%\work_btc"
if exist "%OUTPUT_DIR%\work_kaspa" rmdir /s /q "%OUTPUT_DIR%\work_kaspa"
if exist "%OUTPUT_DIR%\sim_rm_bitcoin.log" del "%OUTPUT_DIR%\sim_rm_bitcoin.log"
if exist "%OUTPUT_DIR%\sim_rm_kaspa.log" del "%OUTPUT_DIR%\sim_rm_kaspa.log"
if exist "%OUTPUT_DIR%\transcript" del "%OUTPUT_DIR%\transcript"

REM ============================================================
REM 1. rm_bitcoin simulation
REM ============================================================
echo.
echo [1/2] Simulating rm_bitcoin...
cd "%OUTPUT_DIR%"
"%MODELSIM_PATH%\vlib" work_btc
"%MODELSIM_PATH%\vmap" work_btc work_btc
echo Compiling sources...
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\sha256_core_baseline.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\sha256d_real_engine.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\sha256d_multi_engine_hp.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\rm_bitcoin.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\rm_bitcoin_wrapper.v"
"%MODELSIM_PATH%\vlog" -sv -work work_btc +acc "%RTL_DIR%\tb_rm_bitcoin.sv"
echo Running simulation...
"%MODELSIM_PATH%\vsim" -c work_btc.tb_rm_bitcoin -do "run -all" -logfile "%OUTPUT_DIR%\sim_rm_bitcoin.log"
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: rm_bitcoin simulation may have issues (check log)
)

REM ============================================================
REM 2. rm_kaspa simulation
REM ============================================================
echo.
echo [2/2] Simulating rm_kaspa...
cd "%OUTPUT_DIR%"
"%MODELSIM_PATH%\vlib" work_kaspa
"%MODELSIM_PATH%\vmap" work_kaspa work_kaspa
echo Compiling sources...
"%MODELSIM_PATH%\vlog" -sv -work work_kaspa +acc "%RTL_DIR%\sha3_256_pipe_engine_hp.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_kaspa +acc "%RTL_DIR%\rm_kaspa.sv"
"%MODELSIM_PATH%\vlog" -sv -work work_kaspa +acc "%RTL_DIR%\rm_kaspa_wrapper.v"
"%MODELSIM_PATH%\vlog" -sv -work work_kaspa +acc "%RTL_DIR%\tb_rm_kaspa.sv"
echo Running simulation...
"%MODELSIM_PATH%\vsim" -c work_kaspa.tb_rm_kaspa -do "run -all" -logfile "%OUTPUT_DIR%\sim_rm_kaspa.log"
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: rm_kaspa simulation may have issues (check log)
)

echo.
echo ============================================================
echo RESULTS:
echo   rm_bitcoin: %OUTPUT_DIR%\sim_rm_bitcoin.log
echo   rm_kaspa:   %OUTPUT_DIR%\sim_rm_kaspa.log
echo ============================================================
pause
