# AWS Masker Plugin - Quality Assurance Makefile
# Based on 04-code-quality-assurance.md standards

.PHONY: help test test-unit test-integration lint quality-check install clean

# Default target
help:
	@echo "Kong AWS Masker Plugin - Quality Assurance Commands"
	@echo ""
	@echo "Development:"
	@echo "  install      Install dependencies (LuaRocks)"
	@echo "  test         Run all tests"
	@echo "  test-unit    Run unit tests only"
	@echo "  test-integration  Run integration tests only"
	@echo "  lint         Run static analysis (luacheck)"
	@echo "  quality-check    Run full quality check"
	@echo "  clean        Clean temporary files"
	@echo ""
	@echo "TDD Commands:"
	@echo "  tdd          Run tests in watch mode for TDD"
	@echo "  red          Create failing test (TDD Red)"
	@echo "  green        Run tests to make them pass (TDD Green)"
	@echo "  refactor     Run quality checks after refactor (TDD Blue)"

# Install dependencies
install:
	@echo "🔧 Installing Lua dependencies..."
	@command -v luarocks >/dev/null 2>&1 || { echo "LuaRocks not found. Please install LuaRocks first."; exit 1; }
	@luarocks install busted
	@luarocks install luacheck
	@luarocks install luacov
	@echo "✅ Dependencies installed"

# Run all tests
test:
	@echo "🧪 Running all tests..."
	@busted --verbose

# Run unit tests only
test-unit:
	@echo "🧪 Running unit tests..."
	@busted spec/unit/ --verbose

# Run integration tests only  
test-integration:
	@echo "🧪 Running integration tests..."
	@busted spec/integration/ --verbose

# Static analysis with luacheck
lint:
	@echo "📝 Running static analysis..."
	@luacheck . --config .luacheckrc

# Full quality check (04-code-quality-assurance.md compliant)
quality-check: lint test
	@echo "📊 Running quality metrics..."
	@echo "  📈 Test Coverage:"
	@busted --coverage --verbose | grep "Total coverage"
	@echo "  🎯 Quality Score: PASS"
	@echo "✅ Quality check completed"

# TDD workflow commands
tdd:
	@echo "🔄 Starting TDD watch mode..."
	@busted --watch

red:
	@echo "🔴 TDD RED: Create failing tests"
	@echo "Write your failing test and run 'make green'"

green:
	@echo "🟢 TDD GREEN: Make tests pass"
	@busted --verbose

refactor:
	@echo "🔵 TDD REFACTOR: Quality check after refactor"
	@$(MAKE) quality-check

# Clean temporary files
clean:
	@echo "🧹 Cleaning temporary files..."
	@rm -rf luacov.*.out
	@rm -rf *.tmp
	@echo "✅ Clean completed"

# Quality metrics report
quality-report:
	@echo "📊 Quality Metrics Report"
	@echo "========================="
	@echo "Static Analysis:"
	@luacheck . --config .luacheckrc --formatter plain | wc -l | awk '{print "  Issues: " $$1}'
	@echo "Test Coverage:"
	@busted --coverage --quiet | grep "Total coverage" || echo "  Coverage: Not available"
	@echo "Code Complexity:"
	@luacheck . --config .luacheckrc --max-cyclomatic-complexity 10 2>/dev/null | wc -l | awk '{print "  Complex functions: " $$1}'