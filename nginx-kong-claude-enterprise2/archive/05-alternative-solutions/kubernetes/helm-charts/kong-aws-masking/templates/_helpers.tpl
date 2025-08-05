{{/*
Expand the name of the chart.
*/}}
{{- define "kong-aws-masking.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kong-aws-masking.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kong-aws-masking.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kong-aws-masking.labels" -}}
helm.sh/chart: {{ include "kong-aws-masking.chart" . }}
{{ include "kong-aws-masking.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kong-aws-masking
environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kong-aws-masking.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kong-aws-masking.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Redis labels
*/}}
{{- define "kong-aws-masking.redis.labels" -}}
{{ include "kong-aws-masking.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis selector labels
*/}}
{{- define "kong-aws-masking.redis.selectorLabels" -}}
{{ include "kong-aws-masking.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Kong labels
*/}}
{{- define "kong-aws-masking.kong.labels" -}}
{{ include "kong-aws-masking.labels" . }}
app.kubernetes.io/component: kong
{{- end }}

{{/*
Kong selector labels
*/}}
{{- define "kong-aws-masking.kong.selectorLabels" -}}
{{ include "kong-aws-masking.selectorLabels" . }}
app.kubernetes.io/component: kong
{{- end }}

{{/*
Nginx labels
*/}}
{{- define "kong-aws-masking.nginx.labels" -}}
{{ include "kong-aws-masking.labels" . }}
app.kubernetes.io/component: nginx
{{- end }}

{{/*
Nginx selector labels
*/}}
{{- define "kong-aws-masking.nginx.selectorLabels" -}}
{{ include "kong-aws-masking.selectorLabels" . }}
app.kubernetes.io/component: nginx
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kong-aws-masking.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kong-aws-masking.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Redis connection string
*/}}
{{- define "kong-aws-masking.redis.connectionString" -}}
{{- printf "redis://:%s@%s-redis:%d/%d" .Values.redis.config.password (include "kong-aws-masking.fullname" .) (.Values.redis.service.port | int) (.Values.redis.config.database | int) }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "kong-aws-masking.redis.host" -}}
{{- printf "%s-redis" (include "kong-aws-masking.fullname" .) }}
{{- end }}

{{/*
Kong service name
*/}}
{{- define "kong-aws-masking.kong.serviceName" -}}
{{- printf "%s-kong" (include "kong-aws-masking.fullname" .) }}
{{- end }}

{{/*
Nginx service name
*/}}
{{- define "kong-aws-masking.nginx.serviceName" -}}
{{- printf "%s-nginx" (include "kong-aws-masking.fullname" .) }}
{{- end }}

{{/*
Claude SDK service name
*/}}
{{- define "kong-aws-masking.claudeSDK.serviceName" -}}
{{- printf "%s-claude-sdk" (include "kong-aws-masking.fullname" .) }}
{{- end }}

{{/*
Common environment variables
*/}}
{{- define "kong-aws-masking.commonEnv" -}}
- name: TZ
  value: {{ .Values.global.timezone | quote }}
- name: AWS_REGION
  value: {{ .Values.global.region | quote }}
- name: ENVIRONMENT
  value: {{ .Values.global.environment | quote }}
{{- end }}

{{/*
Redis environment variables
*/}}
{{- define "kong-aws-masking.redis.env" -}}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "kong-aws-masking.fullname" . }}-secrets
      key: redis-password
- name: REDIS_HOST
  value: {{ include "kong-aws-masking.redis.host" . }}
- name: REDIS_PORT
  value: {{ .Values.redis.service.port | quote }}
- name: REDIS_DATABASE
  value: {{ .Values.redis.config.database | quote }}
{{- end }}

{{/*
AWS environment variables
*/}}
{{- define "kong-aws-masking.aws.env" -}}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "kong-aws-masking.fullname" . }}-secrets
      key: aws-access-key-id
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "kong-aws-masking.fullname" . }}-secrets
      key: aws-secret-access-key
{{- end }}

{{/*
Claude API environment variables
*/}}
{{- define "kong-aws-masking.claude.env" -}}
- name: ANTHROPIC_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "kong-aws-masking.fullname" . }}-secrets
      key: claude-api-key
{{- end }}