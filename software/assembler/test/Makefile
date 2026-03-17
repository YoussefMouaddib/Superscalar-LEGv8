CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic -O2 -I src
TARGET   := legv8-as
SRCDIR   := src
OBJDIR   := build

SRCS := $(wildcard $(SRCDIR)/*.cpp)
OBJS := $(patsubst $(SRCDIR)/%.cpp, $(OBJDIR)/%.o, $(SRCS))

.PHONY: all clean test

all: $(TARGET)

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/%.o: $(SRCDIR)/%.cpp | $(OBJDIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) $^ -o $@
	@echo "Built $(TARGET)"

# ---------------------------------------------------------------------------
# Test targets
# ---------------------------------------------------------------------------
test: $(TARGET)
	@echo "--- test_all.s (binary + listing) ---"
	./$(TARGET) tests/test_all.s -o tests/test_all.bin -f bin \
	            -l tests/test_all.lst --dump-symbols
	@echo ""
	@echo "--- test_all.s (COE output) ---"
	./$(TARGET) tests/test_all.s -o tests/test_all.coe -f coe
	@echo ""
	@echo "--- test_all.s (Intel HEX) ---"
	./$(TARGET) tests/test_all.s -o tests/test_all.hex -f hex
	@echo ""
	@echo "=== Listing ==="
	@cat tests/test_all.lst
	@echo ""
	@echo "=== COE (first 20 lines) ==="
	@head -25 tests/test_all.coe

test-encoding: $(TARGET)
	@echo "--- Encoding spot checks ---"
	@# ADD X1, X2, X3 should encode to:
	@# opcode=000000 Rd=00001 Rn=00010 Rm=00011 shamt=00000 func=100000
	@# = 0000_0000_0010_0001_1000_0000_0010_0000 = 0x00218020
	@echo "Expected ADD X1,X2,X3 = 0x00218020 (opcode=0 Rd=1 Rn=2 Rm=3 func=32)"
	@echo "Expected ADDI X1,X2,#100 = opcode=0x08<<26 | Rd=1<<21 | Rn=2<<16 | imm=100"
	@./$(TARGET) tests/test_all.s -o /tmp/enc_test.bin -f bin
	@hexdump -C /tmp/enc_test.bin | head -10

clean:
	rm -rf $(OBJDIR) $(TARGET) tests/*.bin tests/*.lst tests/*.coe tests/*.hex
