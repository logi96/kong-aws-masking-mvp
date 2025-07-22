# Export to Private Conversion Log

**Date**: 2025-07-15T05:01:32.229Z
**Processed**: 206 items
**Skipped**: 10 items
**Errors**: 32 items

---

## src/feedback/performance-optimizer.ts

### OptimizationConfig (Line 12)

**Before**:
```typescript
export interface OptimizationConfig {
```

**After**:
```typescript
interface OptimizationConfig {
```

### PerformanceMetrics (Line 4)

**Before**:
```typescript
export interface PerformanceMetrics {
```

**After**:
```typescript
interface PerformanceMetrics {
```

---

## src/feedback/progressive-strategy.ts

### AnalysisStage (Line 12)

**Before**:
```typescript
export interface AnalysisStage {
```

**After**:
```typescript
interface AnalysisStage {
```

### ProgressiveStrategyConfig (Line 4)

**Before**:
```typescript
export interface ProgressiveStrategyConfig {
```

**After**:
```typescript
interface ProgressiveStrategyConfig {
```

---

## test/mocks/redis-mock.ts

### MockRedisTransaction (Line 240)

**Before**:
```typescript
export class MockRedisTransaction {
```

**After**:
```typescript
class MockRedisTransaction {
```

### createMockRedisClient (Line 229)

**Before**:
```typescript
export function createMockRedisClient(): MockRedisClient {
```

**After**:
```typescript
function createMockRedisClient(): MockRedisClient {
```

---

## test/test-doubles/test-factory.ts

### createMockA2AMessageBus (Line 513)

**Before**:
```typescript
export function createMockA2AMessageBus(): MockA2AMessageBus {
```

**After**:
```typescript
function createMockA2AMessageBus(): MockA2AMessageBus {
```

### MockA2AMessageBus (Line 503)

**Before**:
```typescript
export interface MockA2AMessageBus {
```

**After**:
```typescript
interface MockA2AMessageBus {
```

### createMockA2ATaskQueue (Line 451)

**Before**:
```typescript
export function createMockA2ATaskQueue(): MockA2ATaskQueue {
```

**After**:
```typescript
function createMockA2ATaskQueue(): MockA2ATaskQueue {
```

### MockA2ATaskQueue (Line 443)

**Before**:
```typescript
export interface MockA2ATaskQueue {
```

**After**:
```typescript
interface MockA2ATaskQueue {
```

### createMockClickHouseService (Line 419)

**Before**:
```typescript
export function createMockClickHouseService(): MockClickHouseService {
```

**After**:
```typescript
function createMockClickHouseService(): MockClickHouseService {
```

### createMockPostgreSQLService (Line 366)

**Before**:
```typescript
export function createMockPostgreSQLService(): MockPostgreSQLService {
```

**After**:
```typescript
function createMockPostgreSQLService(): MockPostgreSQLService {
```

### createMockFeedbackLoop (Line 324)

**Before**:
```typescript
export function createMockFeedbackLoop(): MockFeedbackLoop {
```

**After**:
```typescript
function createMockFeedbackLoop(): MockFeedbackLoop {
```

### createMockArtifactBuilder (Line 267)

**Before**:
```typescript
export function createMockArtifactBuilder(): MockArtifactBuilder {
```

**After**:
```typescript
function createMockArtifactBuilder(): MockArtifactBuilder {
```

### createMockSmartInvestigatorExecutor (Line 207)

**Before**:
```typescript
export function createMockSmartInvestigatorExecutor(): MockSmartInvestigatorExecutor {
```

**After**:
```typescript
function createMockSmartInvestigatorExecutor(): MockSmartInvestigatorExecutor {
```

### createMockTaskQueue (Line 155)

**Before**:
```typescript
export function createMockTaskQueue(): MockTaskQueue {
```

**After**:
```typescript
function createMockTaskQueue(): MockTaskQueue {
```

### MockTaskQueue (Line 145)

**Before**:
```typescript
export interface MockTaskQueue extends ITaskQueue {
```

**After**:
```typescript
interface MockTaskQueue extends ITaskQueue {
```

### createMockTaskConverter (Line 108)

**Before**:
```typescript
export function createMockTaskConverter(): MockTaskConverter {
```

**After**:
```typescript
function createMockTaskConverter(): MockTaskConverter {
```

### MockTaskConverter (Line 102)

**Before**:
```typescript
export interface MockTaskConverter extends ITaskConverter {
```

**After**:
```typescript
interface MockTaskConverter extends ITaskConverter {
```

### createMockWebhookHandler (Line 43)

**Before**:
```typescript
export function createMockWebhookHandler(): MockWebhookHandler {
```

**After**:
```typescript
function createMockWebhookHandler(): MockWebhookHandler {
```

### MockWebhookHandler (Line 35)

**Before**:
```typescript
export interface MockWebhookHandler extends IWebhookHandler {
```

**After**:
```typescript
interface MockWebhookHandler extends IWebhookHandler {
```

---

## src/agents/strategies/alert-processing-strategy-interfaces.ts

### StrategyError (Line 391)

**Before**:
```typescript
export class StrategyError extends Error {
```

**After**:
```typescript
class StrategyError extends Error {
```

---

## src/agents/strategies/communication-strategy-interfaces.ts

### CommunicationError (Line 591)

**Before**:
```typescript
export class CommunicationError extends Error {
```

**After**:
```typescript
class CommunicationError extends Error {
```

### JsonRpcError (Line 471)

**Before**:
```typescript
export interface JsonRpcError {
```

**After**:
```typescript
interface JsonRpcError {
```

### SecurityConfig (Line 285)

**Before**:
```typescript
export interface SecurityConfig {
```

**After**:
```typescript
interface SecurityConfig {
```

### AuthCredentials (Line 274)

**Before**:
```typescript
export interface AuthCredentials {
```

**After**:
```typescript
interface AuthCredentials {
```

### MessageAcknowledgment (Line 259)

**Before**:
```typescript
export interface MessageAcknowledgment {
```

**After**:
```typescript
interface MessageAcknowledgment {
```

### ChannelStatus (Line 182)

**Before**:
```typescript
export type ChannelStatus = 
```

**After**:
```typescript
type ChannelStatus = 
```

---

## src/agents/strategies/investigation-strategy-interfaces.ts

### InvestigationError (Line 656)

**Before**:
```typescript
export class InvestigationError extends Error {
```

**After**:
```typescript
class InvestigationError extends Error {
```

### TimelineStatistics (Line 634)

**Before**:
```typescript
export interface TimelineStatistics {
```

**After**:
```typescript
interface TimelineStatistics {
```

### Anomaly (Line 594)

**Before**:
```typescript
export interface Anomaly {
```

**After**:
```typescript
interface Anomaly {
```

### AnalysisPattern (Line 582)

**Before**:
```typescript
export interface AnalysisPattern {
```

**After**:
```typescript
interface AnalysisPattern {
```

### AnalysisResult (Line 570)

**Before**:
```typescript
export interface AnalysisResult {
```

**After**:
```typescript
interface AnalysisResult {
```

### CorrelationPattern (Line 560)

**Before**:
```typescript
export interface CorrelationPattern {
```

**After**:
```typescript
interface CorrelationPattern {
```

### CorrelationResult (Line 549)

**Before**:
```typescript
export interface CorrelationResult {
```

**After**:
```typescript
interface CorrelationResult {
```

### TimelineFilter (Line 535)

**Before**:
```typescript
export interface TimelineFilter {
```

**After**:
```typescript
interface TimelineFilter {
```

### NetworkTraceOptions (Line 514)

**Before**:
```typescript
export interface NetworkTraceOptions {
```

**After**:
```typescript
interface NetworkTraceOptions {
```

### ConfigCollectionOptions (Line 505)

**Before**:
```typescript
export interface ConfigCollectionOptions {
```

**After**:
```typescript
interface ConfigCollectionOptions {
```

### EventCollectionOptions (Line 495)

**Before**:
```typescript
export interface EventCollectionOptions {
```

**After**:
```typescript
interface EventCollectionOptions {
```

### MetricsCollectionOptions (Line 485)

**Before**:
```typescript
export interface MetricsCollectionOptions {
```

**After**:
```typescript
interface MetricsCollectionOptions {
```

### LogCollectionOptions (Line 473)

**Before**:
```typescript
export interface LogCollectionOptions {
```

**After**:
```typescript
interface LogCollectionOptions {
```

### StepExecutorCapabilities (Line 457)

**Before**:
```typescript
export interface StepExecutorCapabilities {
```

**After**:
```typescript
interface StepExecutorCapabilities {
```

### PerformanceInfo (Line 396)

**Before**:
```typescript
export interface PerformanceInfo {
```

**After**:
```typescript
interface PerformanceInfo {
```

### InvestigationMetrics (Line 382)

**Before**:
```typescript
export interface InvestigationMetrics {
```

**After**:
```typescript
interface InvestigationMetrics {
```

### RecommendationType (Line 316)

**Before**:
```typescript
export type RecommendationType = 
```

**After**:
```typescript
type RecommendationType = 
```

### FindingType (Line 287)

**Before**:
```typescript
export type FindingType = 
```

**After**:
```typescript
type FindingType = 
```

### StepType (Line 190)

**Before**:
```typescript
export type StepType = 
```

**After**:
```typescript
type StepType = 
```

### StepDependency (Line 181)

**Before**:
```typescript
export interface StepDependency {
```

**After**:
```typescript
interface StepDependency {
```

---

## src/core/commands/command-factory.ts

### BaseCommandFactory (Line 118)

**Before**:
```typescript
export abstract class BaseCommandFactory implements ICommandFactory {
```

**After**:
```typescript
abstract class BaseCommandFactory implements ICommandFactory {
```

---

## src/core/commands/golden-command-sets-refactored.ts

### CommandSet (Line 34)

**Before**:
```typescript
export interface CommandSet {
```

**After**:
```typescript
interface CommandSet {
```

### CommandValidation (Line 29)

**Before**:
```typescript
export interface CommandValidation {
```

**After**:
```typescript
interface CommandValidation {
```

### CommandVariables (Line 21)

**Before**:
```typescript
export interface CommandVariables {
```

**After**:
```typescript
interface CommandVariables {
```

---

## src/core/commands/golden-command-sets.ts

### CommandSet (Line 16)

**Before**:
```typescript
export interface CommandSet {
```

**After**:
```typescript
interface CommandSet {
```

### CommandValidation (Line 11)

**Before**:
```typescript
export interface CommandValidation {
```

**After**:
```typescript
interface CommandValidation {
```

### CommandVariables (Line 5)

**Before**:
```typescript
export interface CommandVariables {
```

**After**:
```typescript
interface CommandVariables {
```

---

## src/core/factories/agent-factory.ts

### AgentFactoryConfig (Line 7)

**Before**:
```typescript
export interface AgentFactoryConfig {
```

**After**:
```typescript
interface AgentFactoryConfig {
```

---

## src/core/rules/business-rule-observer.ts

### BusinessRuleManager (Line 592)

**Before**:
```typescript
export class BusinessRuleManager {
```

**After**:
```typescript
class BusinessRuleManager {
```

### BusinessRuleControllerFactory (Line 565)

**Before**:
```typescript
export class BusinessRuleControllerFactory {
```

**After**:
```typescript
class BusinessRuleControllerFactory {
```

### ProgressiveStrategyObserver (Line 517)

**Before**:
```typescript
export class ProgressiveStrategyObserver implements BusinessRuleObserver {
```

**After**:
```typescript
class ProgressiveStrategyObserver implements BusinessRuleObserver {
```

### DataCompletenessObserver (Line 465)

**Before**:
```typescript
export class DataCompletenessObserver implements BusinessRuleObserver {
```

**After**:
```typescript
class DataCompletenessObserver implements BusinessRuleObserver {
```

### PerformanceThresholdObserver (Line 409)

**Before**:
```typescript
export class PerformanceThresholdObserver implements BusinessRuleObserver {
```

**After**:
```typescript
class PerformanceThresholdObserver implements BusinessRuleObserver {
```

### ConfidenceThresholdObserver (Line 370)

**Before**:
```typescript
export class ConfidenceThresholdObserver implements BusinessRuleObserver {
```

**After**:
```typescript
class ConfidenceThresholdObserver implements BusinessRuleObserver {
```

### DefaultBusinessRuleController (Line 53)

**Before**:
```typescript
export class DefaultBusinessRuleController implements BusinessRuleController {
```

**After**:
```typescript
class DefaultBusinessRuleController implements BusinessRuleController {
```

### BusinessRuleSubject (Line 35)

**Before**:
```typescript
export interface BusinessRuleSubject {
```

**After**:
```typescript
interface BusinessRuleSubject {
```

---

## src/core/strategies/StrategyRegistry.ts

### StrategyRegistrationError (Line 217)

**Before**:
```typescript
export class StrategyRegistrationError extends Error {
```

**After**:
```typescript
class StrategyRegistrationError extends Error {
```

### UnsupportedAlertTypeError (Line 207)

**Before**:
```typescript
export class UnsupportedAlertTypeError extends Error {
```

**After**:
```typescript
class UnsupportedAlertTypeError extends Error {
```

### StrategyInfo (Line 198)

**Before**:
```typescript
export interface StrategyInfo {
```

**After**:
```typescript
interface StrategyInfo {
```

---

## src/infrastructure/config/ConfigurationLoader.ts

### ConfigurationError (Line 243)

**Before**:
```typescript
export class ConfigurationError extends Error {
```

**After**:
```typescript
class ConfigurationError extends Error {
```

---

## src/infrastructure/config/types.ts

### isConfigurationDefaults (Line 274)

**Before**:
```typescript
export function isConfigurationDefaults(obj: unknown): obj is ConfigurationDefaults {
```

**After**:
```typescript
function isConfigurationDefaults(obj: unknown): obj is ConfigurationDefaults {
```

### EnvironmentConfig (Line 80)

**Before**:
```typescript
export interface EnvironmentConfig {
```

**After**:
```typescript
interface EnvironmentConfig {
```

### ConfigurationDefaults (Line 44)

**Before**:
```typescript
export interface ConfigurationDefaults {
```

**After**:
```typescript
interface ConfigurationDefaults {
```

---

## src/infrastructure/di/index.ts

### DEFAULT_DI_CONFIG (Line 67)

**Before**:
```typescript
export const DEFAULT_DI_CONFIG: DIConfiguration = {
```

**After**:
```typescript
const DEFAULT_DI_CONFIG: DIConfiguration = {
```

### DIConfiguration (Line 56)

**Before**:
```typescript
export interface DIConfiguration {
```

**After**:
```typescript
interface DIConfiguration {
```

---

## src/infrastructure/di/testing.ts

### MockImplementations (Line 52)

**Before**:
```typescript
export const MockImplementations = {
```

**After**:
```typescript
const MockImplementations = {
```

---

## src/infrastructure/di/tokens.ts

### getAllTokenNames (Line 121)

**Before**:
```typescript
export function getAllTokenNames(): string[] {
```

**After**:
```typescript
function getAllTokenNames(): string[] {
```

### TOKEN_REGISTRY (Line 75)

**Before**:
```typescript
export const TOKEN_REGISTRY = {
```

**After**:
```typescript
const TOKEN_REGISTRY = {
```

---

## src/infrastructure/queue/task-queue.ts

### TaskQueue (Line 15)

**Before**:
```typescript
export class TaskQueue {
```

**After**:
```typescript
class TaskQueue {
```

### TaskQueueOptions (Line 5)

**Before**:
```typescript
export interface TaskQueueOptions {
```

**After**:
```typescript
interface TaskQueueOptions {
```

---

## src/shared/a2a/agent-registry.ts

### A2AAgentRegistryConfig (Line 5)

**Before**:
```typescript
export interface A2AAgentRegistryConfig {
```

**After**:
```typescript
interface A2AAgentRegistryConfig {
```

---

## src/shared/a2a/optimized-message-bus.ts

### StructuredLogger (Line 171)

**Before**:
```typescript
export interface StructuredLogger {
```

**After**:
```typescript
interface StructuredLogger {
```

### PerformanceMetric (Line 157)

**Before**:
```typescript
export interface PerformanceMetric {
```

**After**:
```typescript
interface PerformanceMetric {
```

### OptimizedMessageHandler (Line 152)

**Before**:
```typescript
export type OptimizedMessageHandler = (message: A2AMessage | { batch: A2AMessage[] }) => Promise<void> | void;
```

**After**:
```typescript
type OptimizedMessageHandler = (message: A2AMessage | { batch: A2AMessage[] }) => Promise<void> | void;
```

### MessageTrace (Line 138)

**Before**:
```typescript
export interface MessageTrace {
```

**After**:
```typescript
interface MessageTrace {
```

### TracingConfig (Line 130)

**Before**:
```typescript
export interface TracingConfig {
```

**After**:
```typescript
interface TracingConfig {
```

### PersistenceConfig (Line 121)

**Before**:
```typescript
export interface PersistenceConfig {
```

**After**:
```typescript
interface PersistenceConfig {
```

### DeduplicationConfig (Line 113)

**Before**:
```typescript
export interface DeduplicationConfig {
```

**After**:
```typescript
interface DeduplicationConfig {
```

### CircuitBreakerState (Line 104)

**Before**:
```typescript
export interface CircuitBreakerState {
```

**After**:
```typescript
interface CircuitBreakerState {
```

### SubscriberMetrics (Line 94)

**Before**:
```typescript
export interface SubscriberMetrics {
```

**After**:
```typescript
interface SubscriberMetrics {
```

### MessageBusMetrics (Line 81)

**Before**:
```typescript
export interface MessageBusMetrics {
```

**After**:
```typescript
interface MessageBusMetrics {
```

### SubscriptionOptions (Line 73)

**Before**:
```typescript
export interface SubscriptionOptions {
```

**After**:
```typescript
interface SubscriptionOptions {
```

### BackpressureConfig (Line 65)

**Before**:
```typescript
export interface BackpressureConfig {
```

**After**:
```typescript
interface BackpressureConfig {
```

### CircuitBreakerConfig (Line 56)

**Before**:
```typescript
export interface CircuitBreakerConfig {
```

**After**:
```typescript
interface CircuitBreakerConfig {
```

### PriorityLimits (Line 43)

**Before**:
```typescript
export interface PriorityLimits {
```

**After**:
```typescript
interface PriorityLimits {
```

### BatchConfig (Line 35)

**Before**:
```typescript
export interface BatchConfig {
```

**After**:
```typescript
interface BatchConfig {
```

### OptimizedMessageBusConfig (Line 20)

**Before**:
```typescript
export interface OptimizedMessageBusConfig {
```

**After**:
```typescript
interface OptimizedMessageBusConfig {
```

### LoadBalancingStrategy (Line 15)

**Before**:
```typescript
export type LoadBalancingStrategy = 'round_robin' | 'least_connections' | 'weighted' | 'random';
```

**After**:
```typescript
type LoadBalancingStrategy = 'round_robin' | 'least_connections' | 'weighted' | 'random';
```

---

## src/shared/a2a/types.ts

### Skill (Line 241)

**Before**:
```typescript
export interface Skill {
```

**After**:
```typescript
interface Skill {
```

---

## src/shared/monitoring/alerting-rules.ts

### KubernetesServiceMonitor (Line 34)

**Before**:
```typescript
export interface KubernetesServiceMonitor {
```

**After**:
```typescript
interface KubernetesServiceMonitor {
```

### KubernetesPrometheusRule (Line 20)

**Before**:
```typescript
export interface KubernetesPrometheusRule {
```

**After**:
```typescript
interface KubernetesPrometheusRule {
```

---

## src/shared/monitoring/auto-recovery.ts

### AutoRecoveryConfig (Line 36)

**Before**:
```typescript
export interface AutoRecoveryConfig {
```

**After**:
```typescript
interface AutoRecoveryConfig {
```

### CircuitBreakerStatus (Line 30)

**Before**:
```typescript
export interface CircuitBreakerStatus {
```

**After**:
```typescript
interface CircuitBreakerStatus {
```

### RecoveryMetrics (Line 20)

**Before**:
```typescript
export interface RecoveryMetrics {
```

**After**:
```typescript
interface RecoveryMetrics {
```

### RecoveryResult (Line 13)

**Before**:
```typescript
export interface RecoveryResult {
```

**After**:
```typescript
interface RecoveryResult {
```

---

## src/shared/monitoring/enhanced-health-check.ts

### DetailedHealth (Line 73)

**Before**:
```typescript
export interface DetailedHealth extends SystemHealth {
```

**After**:
```typescript
interface DetailedHealth extends SystemHealth {
```

### ReadinessProbe (Line 65)

**Before**:
```typescript
export interface ReadinessProbe {
```

**After**:
```typescript
interface ReadinessProbe {
```

### LivenessProbe (Line 59)

**Before**:
```typescript
export interface LivenessProbe {
```

**After**:
```typescript
interface LivenessProbe {
```

### HealthMetrics (Line 50)

**Before**:
```typescript
export interface HealthMetrics {
```

**After**:
```typescript
interface HealthMetrics {
```

### ComponentConfig (Line 26)

**Before**:
```typescript
export interface ComponentConfig {
```

**After**:
```typescript
interface ComponentConfig {
```

### HealthCheckFunction (Line 22)

**Before**:
```typescript
export interface HealthCheckFunction {
```

**After**:
```typescript
interface HealthCheckFunction {
```

### ComponentHealth (Line 14)

**Before**:
```typescript
export interface ComponentHealth {
```

**After**:
```typescript
interface ComponentHealth {
```

### ExpressHandler (Line 12)

**Before**:
```typescript
export type ExpressHandler = (req: Request, res: Response) => void;
```

**After**:
```typescript
type ExpressHandler = (req: Request, res: Response) => void;
```

### OtelService (Line 6)

**Before**:
```typescript
export interface OtelService {
```

**After**:
```typescript
interface OtelService {
```

---

## src/shared/monitoring/monitoring-integration.ts

### MonitoringHealthStatus (Line 42)

**Before**:
```typescript
export interface MonitoringHealthStatus {
```

**After**:
```typescript
interface MonitoringHealthStatus {
```

---

## src/shared/quality/any-type-detector.ts

### ViolationSeverity (Line 24)

**Before**:
```typescript
export type ViolationSeverity = 'error' | 'warning';
```

**After**:
```typescript
type ViolationSeverity = 'error' | 'warning';
```

---

## src/shared/quality/compliance-checker.ts

### ClaudeMdComplianceChecker (Line 105)

**Before**:
```typescript
export class ClaudeMdComplianceChecker {
```

**After**:
```typescript
class ClaudeMdComplianceChecker {
```

### CodeQualityMetrics (Line 89)

**Before**:
```typescript
export interface CodeQualityMetrics {
```

**After**:
```typescript
interface CodeQualityMetrics {
```

### TestCoverageSummary (Line 73)

**Before**:
```typescript
export interface TestCoverageSummary {
```

**After**:
```typescript
interface TestCoverageSummary {
```

### ComplianceReport (Line 53)

**Before**:
```typescript
export interface ComplianceReport {
```

**After**:
```typescript
interface ComplianceReport {
```

### ComplianceViolationType (Line 38)

**Before**:
```typescript
export type ComplianceViolationType =
```

**After**:
```typescript
type ComplianceViolationType =
```

### ComplianceViolation (Line 18)

**Before**:
```typescript
export interface ComplianceViolation {
```

**After**:
```typescript
interface ComplianceViolation {
```

---

## src/shared/quality/core-rule-engine.ts

### RuleConfiguration (Line 133)

**Before**:
```typescript
export interface RuleConfiguration {
```

**After**:
```typescript
interface RuleConfiguration {
```

---

## src/shared/quality/execution-analyzer.ts

### ExecutionAnalysisResult (Line 7)

**Before**:
```typescript
export interface ExecutionAnalysisResult {
```

**After**:
```typescript
interface ExecutionAnalysisResult {
```

### IncompleteIssue (Line 1)

**Before**:
```typescript
export interface IncompleteIssue {
```

**After**:
```typescript
interface IncompleteIssue {
```

---

## src/shared/quality/index.ts

### CLIUtils (Line 114)

**Before**:
```typescript
export class CLIUtils {
```

**After**:
```typescript
class CLIUtils {
```

### CLAUDE_PATTERNS (Line 46)

**Before**:
```typescript
export const CLAUDE_PATTERNS = {
```

**After**:
```typescript
const CLAUDE_PATTERNS = {
```

---

## src/shared/quality/security-coverage.ts

### SecurityModuleType (Line 58)

**Before**:
```typescript
export type SecurityModuleType = 
```

**After**:
```typescript
type SecurityModuleType = 
```

### SecurityModuleReport (Line 36)

**Before**:
```typescript
export interface SecurityModuleReport {
```

**After**:
```typescript
interface SecurityModuleReport {
```

---

## src/shared/quality/types.ts

### QualityViolationType (Line 16)

**Before**:
```typescript
export type QualityViolationType = 
```

**After**:
```typescript
type QualityViolationType = 
```

---

## src/shared/security/audit-logger.ts

### SecurityViolationEvent (Line 37)

**Before**:
```typescript
export interface SecurityViolationEvent {
```

**After**:
```typescript
interface SecurityViolationEvent {
```

### AuthenticationEvent (Line 29)

**Before**:
```typescript
export interface AuthenticationEvent {
```

**After**:
```typescript
interface AuthenticationEvent {
```

### CommandExecutionEvent (Line 21)

**Before**:
```typescript
export interface CommandExecutionEvent {
```

**After**:
```typescript
interface CommandExecutionEvent {
```

### AuditSeverity (Line 10)

**Before**:
```typescript
export type AuditSeverity = 'critical' | 'warning' | 'info' | 'debug';
```

**After**:
```typescript
type AuditSeverity = 'critical' | 'warning' | 'info' | 'debug';
```

---

## src/shared/testing/mock-k8s-strategy.ts

### MockK8sStrategy (Line 24)

**Before**:
```typescript
export class MockK8sStrategy {
```

**After**:
```typescript
class MockK8sStrategy {
```

---

## src/shared/testing/mock-kubernetes-executor.ts

### MockKubernetesExecutor (Line 16)

**Before**:
```typescript
export class MockKubernetesExecutor implements KubernetesExecutorInterface {
```

**After**:
```typescript
class MockKubernetesExecutor implements KubernetesExecutorInterface {
```

### KubernetesExecutorInterface (Line 9)

**Before**:
```typescript
export interface KubernetesExecutorInterface {
```

**After**:
```typescript
interface KubernetesExecutorInterface {
```

---

## src/shared/testing/real-k8s-executor.ts

### KubernetesExecutorInterface (Line 21)

**Before**:
```typescript
export interface KubernetesExecutorInterface {
```

**After**:
```typescript
interface KubernetesExecutorInterface {
```

### K8sExecutionResult (Line 12)

**Before**:
```typescript
export interface K8sExecutionResult {
```

**After**:
```typescript
interface K8sExecutionResult {
```

---

## src/shared/types/api-response.ts

### HealthResponse (Line 27)

**Before**:
```typescript
export interface HealthResponse {
```

**After**:
```typescript
interface HealthResponse {
```

### ApiErrorResponse (Line 15)

**Before**:
```typescript
export interface ApiErrorResponse {
```

**After**:
```typescript
interface ApiErrorResponse {
```

### ApiResponse (Line 4)

**Before**:
```typescript
export interface ApiResponse<T = unknown> {
```

**After**:
```typescript
interface ApiResponse<T = unknown> {
```

---

## src/shared/types/database.ts

### InvestigationStatus (Line 5)

**Before**:
```typescript
export type InvestigationStatus = 'pending' | 'in_progress' | 'completed' | 'failed' | 'timeout';
```

**After**:
```typescript
type InvestigationStatus = 'pending' | 'in_progress' | 'completed' | 'failed' | 'timeout';
```

### TaskStatus (Line 4)

**Before**:
```typescript
export type TaskStatus = 'submitted' | 'working' | 'completed' | 'failed';
```

**After**:
```typescript
type TaskStatus = 'submitted' | 'working' | 'completed' | 'failed';
```

### AlertType (Line 3)

**Before**:
```typescript
export type AlertType = 'PodCrashLoopBackOff' | 'HighMemory' | 'NetworkLatency';
```

**After**:
```typescript
type AlertType = 'PodCrashLoopBackOff' | 'HighMemory' | 'NetworkLatency';
```

---

## src/shared/types/test-utils.ts

### isObject (Line 39)

**Before**:
```typescript
export function isObject(value: unknown): value is Record<string, unknown> {
```

**After**:
```typescript
function isObject(value: unknown): value is Record<string, unknown> {
```

### DeepPartial (Line 9)

**Before**:
```typescript
export type DeepPartial<T> = {
```

**After**:
```typescript
type DeepPartial<T> = {
```

---

## src/agents/gateway/src/a2a-gateway-agent.ts

### A2AGatewayAgentConfig (Line 12)

**Before**:
```typescript
export interface A2AGatewayAgentConfig {
```

**After**:
```typescript
interface A2AGatewayAgentConfig {
```

---

## src/agents/k8s-health-analyzer/src/a2a-consumer.ts

### K8sHealthAnalyzerA2AConsumer (Line 9)

**Before**:
```typescript
export interface K8sHealthAnalyzerA2AConsumer {
```

**After**:
```typescript
interface K8sHealthAnalyzerA2AConsumer {
```

---

## src/agents/k8s-health-analyzer/src/k8s-health-analyzer.ts

### AnalyzerCapabilities (Line 88)

**Before**:
```typescript
export interface AnalyzerCapabilities {
```

**After**:
```typescript
interface AnalyzerCapabilities {
```

### IK8sHealthAnalyzer (Line 78)

**Before**:
```typescript
export interface IK8sHealthAnalyzer {
```

**After**:
```typescript
interface IK8sHealthAnalyzer {
```

### StorageInfo (Line 72)

**Before**:
```typescript
export interface StorageInfo {
```

**After**:
```typescript
interface StorageInfo {
```

### NetworkInfo (Line 66)

**Before**:
```typescript
export interface NetworkInfo {
```

**After**:
```typescript
interface NetworkInfo {
```

### NodeInfo (Line 59)

**Before**:
```typescript
export interface NodeInfo {
```

**After**:
```typescript
interface NodeInfo {
```

### WorkloadInfo (Line 52)

**Before**:
```typescript
export interface WorkloadInfo {
```

**After**:
```typescript
interface WorkloadInfo {
```

### NamespaceInfo (Line 46)

**Before**:
```typescript
export interface NamespaceInfo {
```

**After**:
```typescript
interface NamespaceInfo {
```

### ClusterInfo (Line 40)

**Before**:
```typescript
export interface ClusterInfo {
```

**After**:
```typescript
interface ClusterInfo {
```

### K8sContext (Line 30)

**Before**:
```typescript
export interface K8sContext {
```

**After**:
```typescript
interface K8sContext {
```

### Evidence (Line 23)

**Before**:
```typescript
export interface Evidence {
```

**After**:
```typescript
interface Evidence {
```

---

## src/agents/smart-investigator/src/a2a-consumer.ts

### A2AConsumer (Line 12)

**Before**:
```typescript
export interface A2AConsumer {
```

**After**:
```typescript
interface A2AConsumer {
```

---

## src/agents/smart-investigator/src/smart-investigator-agent-refactored.ts

### SmartInvestigatorAgent (Line 42)

**Before**:
```typescript
export class SmartInvestigatorAgent implements ISmartInvestigatorAgent {
```

**After**:
```typescript
class SmartInvestigatorAgent implements ISmartInvestigatorAgent {
```

---

## src/core/strategies/di/strategy-container.ts

### configureAlertStrategies (Line 28)

**Before**:
```typescript
export function configureAlertStrategies(): void {
```

**After**:
```typescript
function configureAlertStrategies(): void {
```

---

## src/core/strategies/test/strategy-runtime-test.ts

### runStrategyRuntimeTests (Line 29)

**Before**:
```typescript
export async function runStrategyRuntimeTests(): Promise<void> {
```

**After**:
```typescript
async function runStrategyRuntimeTests(): Promise<void> {
```

---

## src/shared/monitoring/otel/metrics-manager.ts

### MockGauge (Line 51)

**Before**:
```typescript
export class MockGauge implements Gauge {
```

**After**:
```typescript
class MockGauge implements Gauge {
```

### MockHistogram (Line 38)

**Before**:
```typescript
export class MockHistogram implements Histogram {
```

**After**:
```typescript
class MockHistogram implements Histogram {
```

### MockCounter (Line 25)

**Before**:
```typescript
export class MockCounter implements Counter {
```

**After**:
```typescript
class MockCounter implements Counter {
```

### Gauge (Line 15)

**Before**:
```typescript
export interface Gauge {
```

**After**:
```typescript
interface Gauge {
```

### ObservableResult (Line 11)

**Before**:
```typescript
export interface ObservableResult {
```

**After**:
```typescript
interface ObservableResult {
```

### Histogram (Line 7)

**Before**:
```typescript
export interface Histogram {
```

**After**:
```typescript
interface Histogram {
```

### Counter (Line 3)

**Before**:
```typescript
export interface Counter {
```

**After**:
```typescript
interface Counter {
```

---

## src/shared/monitoring/otel/span-manager.ts

### MockSpan (Line 20)

**Before**:
```typescript
export class MockSpan implements Span {
```

**After**:
```typescript
class MockSpan implements Span {
```

---

## src/agents/gateway/src/a2a/types.ts

### JsonRpcError (Line 44)

**Before**:
```typescript
export interface JsonRpcError {
```

**After**:
```typescript
interface JsonRpcError {
```

---

## src/agents/gateway/src/modules/a2a-router.ts

### A2ARouterOptions (Line 28)

**Before**:
```typescript
export interface A2ARouterOptions {
```

**After**:
```typescript
interface A2ARouterOptions {
```

---

## src/agents/gateway/src/modules/alert-processor.ts

### AlertProcessingOptions (Line 28)

**Before**:
```typescript
export interface AlertProcessingOptions {
```

**After**:
```typescript
interface AlertProcessingOptions {
```

---

## src/agents/gateway/src/modules/database-initializer.ts

### DatabaseInitializerOptions (Line 10)

**Before**:
```typescript
export interface DatabaseInitializerOptions {
```

**After**:
```typescript
interface DatabaseInitializerOptions {
```

---

## src/agents/gateway/src/modules/health-monitor.ts

### HealthCheckOptions (Line 17)

**Before**:
```typescript
export interface HealthCheckOptions {
```

**After**:
```typescript
interface HealthCheckOptions {
```

### HealthStatus (Line 6)

**Before**:
```typescript
export interface HealthStatus {
```

**After**:
```typescript
interface HealthStatus {
```

---

## src/agents/gateway/src/modules/metrics-collector.ts

### MetricsData (Line 24)

**Before**:
```typescript
export interface MetricsData {
```

**After**:
```typescript
interface MetricsData {
```

### QueueMetrics (Line 19)

**Before**:
```typescript
export interface QueueMetrics {
```

**After**:
```typescript
interface QueueMetrics {
```

### DatabaseMetrics (Line 14)

**Before**:
```typescript
export interface DatabaseMetrics {
```

**After**:
```typescript
interface DatabaseMetrics {
```

### PerformanceMetrics (Line 9)

**Before**:
```typescript
export interface PerformanceMetrics {
```

**After**:
```typescript
interface PerformanceMetrics {
```

### WebhookMetrics (Line 1)

**Before**:
```typescript
export interface WebhookMetrics {
```

**After**:
```typescript
interface WebhookMetrics {
```

---

## src/agents/k8s-health-analyzer/src/core/kubernetes-executor.ts

### IKubernetesExecutor (Line 1)

**Before**:
```typescript
export interface IKubernetesExecutor {
```

**After**:
```typescript
interface IKubernetesExecutor {
```

---

## src/agents/k8s-health-analyzer/src/storm/alert-deduplicator.ts

### DeduplicationResult (Line 7)

**Before**:
```typescript
export interface DeduplicationResult {
```

**After**:
```typescript
interface DeduplicationResult {
```

### IAlertDeduplicator (Line 3)

**Before**:
```typescript
export interface IAlertDeduplicator {
```

**After**:
```typescript
interface IAlertDeduplicator {
```

---

## src/agents/k8s-health-analyzer/src/storm/circuit-breaker.ts

### CircuitBreakerOptions (Line 12)

**Before**:
```typescript
export interface CircuitBreakerOptions {
```

**After**:
```typescript
interface CircuitBreakerOptions {
```

### ICircuitBreaker (Line 5)

**Before**:
```typescript
export interface ICircuitBreaker {
```

**After**:
```typescript
interface ICircuitBreaker {
```

---

## src/agents/k8s-health-analyzer/src/storm/intelligent-deduplicator.ts

### DeduplicationOptions (Line 5)

**Before**:
```typescript
export interface DeduplicationOptions {
```

**After**:
```typescript
interface DeduplicationOptions {
```

---

## src/agents/k8s-health-analyzer/src/types/index.ts

### ContainerState (Line 211)

**Before**:
```typescript
export interface ContainerState {
```

**After**:
```typescript
interface ContainerState {
```

### ContainerStatus (Line 203)

**Before**:
```typescript
export interface ContainerStatus {
```

**After**:
```typescript
interface ContainerStatus {
```

### PodCondition (Line 195)

**Before**:
```typescript
export interface PodCondition {
```

**After**:
```typescript
interface PodCondition {
```

### LogInfo (Line 188)

**Before**:
```typescript
export interface LogInfo {
```

**After**:
```typescript
interface LogInfo {
```

### RBACIssue (Line 157)

**Before**:
```typescript
export interface RBACIssue {
```

**After**:
```typescript
interface RBACIssue {
```

### ServiceAccountInfo (Line 150)

**Before**:
```typescript
export interface ServiceAccountInfo {
```

**After**:
```typescript
interface ServiceAccountInfo {
```

### ResourceUsage (Line 67)

**Before**:
```typescript
export interface ResourceUsage {
```

**After**:
```typescript
interface ResourceUsage {
```

---

## src/agents/smart-investigator/src/a2a/k8s-health-analyzer-client.ts

### AlertStormResult (Line 18)

**Before**:
```typescript
export interface AlertStormResult {
```

**After**:
```typescript
interface AlertStormResult {
```

---

## src/agents/smart-investigator/src/modules/a2a-manager.ts

### A2AStatus (Line 16)

**Before**:
```typescript
export interface A2AStatus {
```

**After**:
```typescript
interface A2AStatus {
```

### A2AConfig (Line 6)

**Before**:
```typescript
export interface A2AConfig {
```

**After**:
```typescript
interface A2AConfig {
```

---

## src/agents/smart-investigator/src/modules/alert-analyzer.ts

### AnalysisEvidence (Line 42)

**Before**:
```typescript
export interface AnalysisEvidence {
```

**After**:
```typescript
interface AnalysisEvidence {
```

### AlertContext (Line 37)

**Before**:
```typescript
export interface AlertContext {
```

**After**:
```typescript
interface AlertContext {
```

### CommandOutput (Line 32)

**Before**:
```typescript
export interface CommandOutput {
```

**After**:
```typescript
interface CommandOutput {
```

---

## src/agents/smart-investigator/src/modules/artifact-builder.ts

### AlertType (Line 13)

**Before**:
```typescript
export type { AlertType, Artifact, ExecutionResult, InvestigationData, InvestigationMetrics, DetailedRecommendation };
```

**After**:
```typescript
type { AlertType, Artifact, ExecutionResult, InvestigationData, InvestigationMetrics, DetailedRecommendation };
```

---

## src/agents/smart-investigator/src/modules/database-manager.ts

### DatabaseConnections (Line 16)

**Before**:
```typescript
export interface DatabaseConnections {
```

**After**:
```typescript
interface DatabaseConnections {
```

---

## src/agents/smart-investigator/src/modules/feedback-loop.ts

### InvestigationResult (Line 14)

**Before**:
```typescript
export type { InvestigationResult, RetryContext, EnhancementResult, FeedbackMetrics };
```

**After**:
```typescript
type { InvestigationResult, RetryContext, EnhancementResult, FeedbackMetrics };
```

---

## src/agents/smart-investigator/src/modules/investigation-coordinator.ts

### EnhancementDetails (Line 33)

**Before**:
```typescript
export interface EnhancementDetails {
```

**After**:
```typescript
interface EnhancementDetails {
```

### ProcessingOptions (Line 23)

**Before**:
```typescript
export interface ProcessingOptions {
```

**After**:
```typescript
interface ProcessingOptions {
```

---

## src/agents/smart-investigator/src/types/a2a-server.ts

### AgentSkill (Line 142)

**Before**:
```typescript
export interface AgentSkill {
```

**After**:
```typescript
interface AgentSkill {
```

### JsonRpcError (Line 47)

**Before**:
```typescript
export interface JsonRpcError {
```

**After**:
```typescript
interface JsonRpcError {
```

---

