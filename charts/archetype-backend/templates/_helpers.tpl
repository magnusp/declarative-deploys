{{- define "archetype-backend.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "archetype-backend.labels" -}}
app.kubernetes.io/name: {{ include "archetype-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "archetype-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "archetype-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
