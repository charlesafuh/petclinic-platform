{{/*
Service name = release name unless explicitly overridden. Used for metadata.name,
the app.kubernetes.io/name label, selectors, Service, ServiceAccount and ConfigMap.
*/}}
{{- define "petclinic-service.name" -}}
{{- default .Release.Name .Values.nameOverride -}}
{{- end -}}

{{/*
Target namespace: explicit .Values.namespace (set per-env) else the release namespace.
*/}}
{{- define "petclinic-service.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end -}}

{{/*
Fully-qualified image reference. image.registry already includes the petclinic-{env}
path (set per-env); image.name is per-service; image.tag is set by CI.
*/}}
{{- define "petclinic-service.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.name (.Values.image.tag | toString) -}}
{{- end -}}

{{/*
Standard labels (per .claude/rules/kubernetes.md).
*/}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.name" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: kubectl
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{/*
Selector labels (immutable subset).
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.name" . }}
{{- end -}}
