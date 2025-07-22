# 📊 Dead Code Risk Assessment Report

**Generated**: 2025-07-15T04:34:41.283Z
**Total Dead Code Items**: 902

## 🎯 Risk Distribution

| Risk Level | Count | Percentage |
|------------|-------|------------|
| 🟢 LOW | 212 | 23.5% |
| 🟡 MEDIUM | 79 | 8.8% |
| 🔴 HIGH | 611 | 67.7% |

## 📈 Type Distribution

| Type | Count |
|------|-------|
| class | 575 |
| type | 123 |
| interface | 75 |
| function | 72 |
| unknown | 31 |
| test-util | 21 |
| test | 5 |

---

## 🟢 LOW RISK Items (212)
**Safe to delete - mostly test utilities and internal module code**

- `src/feedback/command-cache.ts:4` - **CacheEntry** (used in module)
- `src/feedback/command-cache.ts:13` - **CommandCacheConfig** (used in module)
- `src/feedback/data-completeness.ts:3` - **DataCompletenessConfig** (used in module)
- `src/feedback/performance-optimizer.ts:4` - **PerformanceMetrics** (used in module)
- `src/feedback/performance-optimizer.ts:12` - **OptimizationConfig** (used in module)
- `src/feedback/progressive-strategy.ts:12` - **AnalysisStage** (used in module)
- `test/integration/a2a-end-to-end.test.ts:690` - **AlertMessageBuilder** (used in module)
- `test/integration/a2a-end-to-end.test.ts:691` - **createE2ETestContext** (used in module)
- `test/integration/a2a-end-to-end.test.ts:692` - **gatewayAgentCard** (used in module)
- `test/integration/a2a-end-to-end.test.ts:693` - **investigatorAgentCard** (used in module)
- `test/mocks/redis-mock.ts:229` - **createMockRedisClient** (used in module)
- `test/mocks/redis-mock.ts:240` - **MockRedisTransaction** (used in module)
- `test/mocks/redis-mock.ts:265` - **mockRedisModule** 
- `test/test-doubles/test-factory.ts:43` - **createMockWebhookHandler** (used in module)
- `test/test-doubles/test-factory.ts:108` - **createMockTaskConverter** (used in module)
- `test/test-doubles/test-factory.ts:155` - **createMockTaskQueue** (used in module)
- `test/test-doubles/test-factory.ts:207` - **createMockSmartInvestigatorExecutor** (used in module)
- `test/test-doubles/test-factory.ts:267` - **createMockArtifactBuilder** (used in module)
- `test/test-doubles/test-factory.ts:324` - **createMockFeedbackLoop** (used in module)
- `test/test-doubles/test-factory.ts:366` - **createMockPostgreSQLService** (used in module)

... and 192 more items

---

## 🟡 MEDIUM RISK Items (79)
**Requires review before deletion**

- `src/core/commands/golden-command-sets.ts:27` - **GoldenCommandSets** [class]
- `src/core/investigation/command-pattern.ts:262` - **KubectlLogsCommand** [class]
- `src/core/investigation/command-pattern.ts:315` - **KubectlDescribeCommand** [class]
- `src/core/investigation/command-pattern.ts:367` - **InvestigationCommand** [class]
- `src/core/investigation/command-pattern.ts:493` - **PriorityCommandQueue** [class]
- `src/core/investigation/command-pattern.ts:586` - **CommandHistory** [class]
- `src/core/rules/business-rule-observer.ts:610` - **businessRuleManager** [function]
- `src/infrastructure/adapters/adapter-helpers.ts:42` - **createTestAdapterManager** [function]
- `src/infrastructure/adapters/adapter-helpers.ts:62` - **validateAdapterConfigs** [function]
- `src/infrastructure/adapters/adapter-helpers.ts:120` - **getAdapterHealthSummary** [function]
- `src/infrastructure/config/types.ts:115` - **ConfigurationSchema** [type]
- `src/infrastructure/config/types.ts:135` - **ConfigurationLoadOptions** [type]
- `src/infrastructure/config/types.ts:174` - **IConfigurationChangeNotifier** [interface]
- `src/infrastructure/config/types.ts:189` - **IConfigurationCache** [interface]
- `src/infrastructure/config/types.ts:222` - **ConfigurationValidationResult** [type]
- `src/infrastructure/config/types.ts:244` - **IConfigurationMigrator** [interface]
- `src/infrastructure/config/types.ts:308` - **CONFIG_CONSTANTS** [type]
- `src/infrastructure/di/decorators.ts:9` - **singleton** [function]
- `src/infrastructure/di/decorators.ts:9` - **autoInjectable** [function]
- `src/infrastructure/di/decorators.ts:9` - **injectAll** [function]

... and 59 more items

---

## 🔴 HIGH RISK Items (611)
**DO NOT DELETE without extensive review**

- `src/feedback/progressive-strategy.ts:4` - **ProgressiveStrategyConfig** [type]
- `src/a2a/task-queue/index.ts:2` - **A2ATaskQueueConfig** [type]
- `src/a2a/task-queue/index.ts:2` - **A2ATask** [class]
- `src/a2a/task-queue/index.ts:2` - **TaskPriority** [class]
- `src/a2a/task-queue/index.ts:2` - **Task** [class]
- `src/a2a/task-queue/index.ts:2` - **TaskStatus** [class]
- `src/a2a/types/index.ts:1` - **AlertType** [type]
- `src/agents/strategies/alert-processing-strategy-interfaces.ts:391` - **StrategyError** [class]
- `src/agents/strategies/alert-processing-strategy-interfaces.ts:459` - **CreateAlertProcessingContext** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:182` - **ChannelStatus** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:259` - **MessageAcknowledgment** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:274` - **AuthCredentials** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:285` - **SecurityConfig** [type]
- `src/agents/strategies/communication-strategy-interfaces.ts:471` - **JsonRpcError** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:591` - **CommunicationError** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:605` - **ChannelError** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:615` - **MessageDeliveryError** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:625` - **ProtocolError** [class]
- `src/agents/strategies/communication-strategy-interfaces.ts:635` - **SecurityError** [class]
- `src/agents/strategies/investigation-strategy-interfaces.ts:181` - **StepDependency** [class]

... and 591 more items

---

## 🛠️ Recommended Actions

### Phase 1: LOW RISK Cleanup (Safe)
```bash
# Review and delete test utilities
grep -r "createMock" src/ test/

# Remove "used in module" items
# These are only used internally and can be made private
```

### Phase 2: MEDIUM RISK Review
1. Check each item for:
   - Dynamic imports
   - Reflection usage
   - External dependencies
2. Create PR for each batch

### Phase 3: HIGH RISK Analysis
1. Never delete DI tokens
2. Check strategy registration
3. Verify public API usage
4. Review with team

---

**Next Step**: Start with LOW RISK items for safe cleanup