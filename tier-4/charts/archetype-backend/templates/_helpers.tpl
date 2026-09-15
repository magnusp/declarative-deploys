{{- define "archetype-backend.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "archetype-backend.labels" -}}
app.kubernetes.io/name: {{ include "archetype-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{/*
Chart.Version can carry OCI build metadata (e.g. "0.1.0+<digest>") when
installed via chartRef from an OCIRepository — "+" isn't a valid label
value character, so it's replaced with "_".
*/}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "archetype-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "archetype-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
