{{/*
Helper templates for the n8n chart.
*/}}

{{- define "n8n.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Default base name for objects that don't have their own explicit override:
fullnameOverride wins outright; otherwise <release>-<name>, collapsed to just
<release> when the release name already contains the chart name.
*/}}
{{- define "n8n.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{ .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- $name := include "n8n.name" . -}}
{{- if contains $name .Release.Name -}}
{{ .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{ printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "n8n.namespace" -}}
{{ default .Release.Namespace .Values.namespace }}
{{- end -}}

{{- define "n8n.serviceName" -}}
{{ default (include "n8n.fullname" .) .Values.service.name }}
{{- end -}}

{{- define "n8n.pvcName" -}}
{{ default (printf "%s-data" (include "n8n.fullname" .)) .Values.persistence.claimName }}
{{- end -}}

{{/* Name of the Secret actually used: existingSecret, or the one this chart creates. */}}
{{- define "n8n.secretName" -}}
{{- if .Values.secrets.create -}}
{{ include "n8n.fullname" . }}-secrets
{{- else -}}
{{ required "existingSecret is required when secrets.create=false" .Values.existingSecret }}
{{- end -}}
{{- end -}}

{{/* Deployment/Service selector labels: fails on {} too, unlike `required`. */}}
{{- define "n8n.selector" -}}
{{- if not .Values.labels.selector -}}
{{ fail "labels.selector is required, e.g. {app: n8n}" }}
{{- end -}}
{{- toYaml .Values.labels.selector -}}
{{- end -}}

{{/* `annotations:` block with the keep policy, or nothing. */}}
{{- define "n8n.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}
