VERILATOR ?= verilator
IVERILOG ?= iverilog
VVP       ?= vvp
PYTHON    ?= python3
YOSYS     ?= yosys

BUILD_DIR := sim/build
WAVE_DIR  := sim/waveforms
LOG_DIR   := sim/logs

VERILATOR_FLAGS := -Wall --timing --assert -Irtl/cpu -Irtl/memory

CPU_PKG      := rtl/cpu/cpu_pkg.sv
CPU_ALU      := rtl/cpu/alu.sv
CPU_REGFILE  := rtl/cpu/regfile.sv
CPU_IMM_GEN  := rtl/cpu/imm_gen.sv
CPU_DECODER  := rtl/cpu/decoder.sv

.PHONY: test test-cpu test-accel-seq test-accel-pipe test-accel-pipe-random test-accel-mmio test-golden test-alu test-regfile \
        test-imm test-decoder test-cpu-core lint lint-cpu lint-alu \
        lint-regfile lint-imm lint-decoder lint-cpu-core lint-accel-seq lint-accel-pipe lint-accel-pipe-random lint-accel-mmio \
        lint-accel-performance \
        synth-accel-seq synth-accel-pipe synth-accel perf-accel compare-accel \
        clean prepare-dirs

SEED        ?= 12345
RANDOM_TXNS ?= 3000

test: prepare-dirs
	bash scripts/run_regression.sh

test-cpu: test-alu test-regfile test-imm test-decoder test-cpu-core

test-accel-seq: prepare-dirs
	$(IVERILOG) -g2012 -Wall -s dot_product_seq_tb \
		-o $(BUILD_DIR)/dot_product_seq_tb.vvp \
		-f filelists/accel_seq.f tb/accelerator/sequential/dot_product_seq_tb.sv
	$(VVP) $(BUILD_DIR)/dot_product_seq_tb.vvp

test-accel-pipe: prepare-dirs
	$(IVERILOG) -g2012 -Wall -s dot_product_pipeline_tb \
		-o $(BUILD_DIR)/dot_product_pipeline_tb.vvp \
		-f filelists/accel_pipe.f tb/accelerator/pipelined/dot_product_pipeline_tb.sv
	$(VVP) $(BUILD_DIR)/dot_product_pipeline_tb.vvp

test-accel-pipe-random: prepare-dirs
	$(IVERILOG) -g2012 -Wall -s dot_product_pipeline_random_tb \
		-o $(BUILD_DIR)/dot_product_pipeline_random_tb.vvp \
		-f filelists/accel_pipe.f tb/accelerator/pipelined/dot_product_pipeline_random_tb.sv
	$(VVP) $(BUILD_DIR)/dot_product_pipeline_random_tb.vvp \
		+SEED=$(SEED) +NUM_TXNS=$(RANDOM_TXNS)

test-accel-mmio: prepare-dirs
	$(IVERILOG) -g2012 -Wall -s dot_product_accel_mmio_tb \
		-o $(BUILD_DIR)/dot_product_accel_mmio_tb.vvp \
		-f filelists/accel_mmio.f tb/accelerator/mmio/dot_product_accel_mmio_tb.sv
	$(VVP) $(BUILD_DIR)/dot_product_accel_mmio_tb.vvp

test-golden:
	$(PYTHON) model/golden_model.py

test-alu: prepare-dirs
	bash scripts/run_verilator_test.sh alu alu_tb \
		$(CPU_PKG) $(CPU_ALU) tb/cpu/alu_tb.sv

test-regfile: prepare-dirs
	bash scripts/run_verilator_test.sh regfile regfile_tb \
		$(CPU_REGFILE) tb/cpu/regfile_tb.sv

test-imm: prepare-dirs
	bash scripts/run_verilator_test.sh imm_gen imm_gen_tb \
		$(CPU_PKG) $(CPU_IMM_GEN) tb/cpu/imm_gen_tb.sv

test-decoder: prepare-dirs
	bash scripts/run_verilator_test.sh decoder decoder_tb \
		$(CPU_PKG) $(CPU_DECODER) tb/cpu/decoder_tb.sv

test-cpu-core: prepare-dirs
	bash scripts/run_verilator_test.sh cpu cpu_core_tb \
		-f filelists/cpu.f tb/cpu/cpu_core_tb.sv

lint: lint-cpu lint-accel-seq lint-accel-pipe lint-accel-pipe-random lint-accel-mmio lint-accel-performance

lint-cpu: lint-alu lint-regfile lint-imm lint-decoder lint-cpu-core

lint-alu: prepare-dirs
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		$(CPU_PKG) $(CPU_ALU) tb/cpu/alu_tb.sv \
		--top-module alu_tb

lint-regfile: prepare-dirs
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		$(CPU_REGFILE) tb/cpu/regfile_tb.sv \
		--top-module regfile_tb

lint-imm: prepare-dirs
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		$(CPU_PKG) $(CPU_IMM_GEN) tb/cpu/imm_gen_tb.sv \
		--top-module imm_gen_tb

lint-decoder: prepare-dirs
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		$(CPU_PKG) $(CPU_DECODER) tb/cpu/decoder_tb.sv \
		--top-module decoder_tb

lint-cpu-core: prepare-dirs
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		-f filelists/cpu.f tb/cpu/cpu_core_tb.sv \
		--top-module cpu_core_tb

lint-accel-seq: prepare-dirs
	$(VERILATOR) -Wall --timing --assert --lint-only \
		-f filelists/accel_seq.f tb/accelerator/sequential/dot_product_seq_tb.sv \
		--top-module dot_product_seq_tb

lint-accel-pipe: prepare-dirs
	$(VERILATOR) -Wall --timing --assert --lint-only \
		-f filelists/accel_pipe.f tb/accelerator/pipelined/dot_product_pipeline_tb.sv \
		--top-module dot_product_pipeline_tb

lint-accel-pipe-random: prepare-dirs
	$(VERILATOR) -Wall --timing --assert --lint-only \
		-f filelists/accel_pipe.f tb/accelerator/pipelined/dot_product_pipeline_random_tb.sv \
		--top-module dot_product_pipeline_random_tb

lint-accel-mmio: prepare-dirs
	$(VERILATOR) -Wall --timing --assert --lint-only \
		-f filelists/accel_mmio.f tb/accelerator/mmio/dot_product_accel_mmio_tb.sv \
		--top-module dot_product_accel_mmio_tb

lint-accel-performance: prepare-dirs
	$(VERILATOR) -Wall --timing --assert --lint-only \
		rtl/accelerator/sequential/dot_product_seq.sv \
		tb/accelerator/performance/dot_product_seq_perf_tb.sv \
		--top-module dot_product_seq_perf_tb
	$(VERILATOR) -Wall --timing --assert --lint-only \
		rtl/accelerator/pipelined/dot_product_pipeline.sv \
		tb/accelerator/performance/dot_product_pipeline_perf_tb.sv \
		--top-module dot_product_pipeline_perf_tb

synth-accel-seq:
	YOSYS=$(YOSYS) bash scripts/synth_accelerators.sh seq

synth-accel-pipe:
	YOSYS=$(YOSYS) bash scripts/synth_accelerators.sh pipe

synth-accel: synth-accel-seq synth-accel-pipe

perf-accel:
	IVERILOG=$(IVERILOG) VVP=$(VVP) bash scripts/run_accel_performance.sh all

compare-accel: synth-accel perf-accel
	YOSYS=$(YOSYS) $(PYTHON) scripts/compare_accelerators.py

prepare-dirs:
	mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)

clean:
	rm -rf $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
