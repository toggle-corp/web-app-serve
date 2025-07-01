{{/*
    Expand the name of the chart.
*/}}
{{- define "web-app-serve.name" -}}
    {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
    Create a default fully qualified app name.
    We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
    If release name contains chart name it will be used as a full name.
    https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names
*/}}
{{- define "web-app-serve.fullname" -}}
    {{- if .Values.fullnameOverride -}}
        {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
        {{- $name := default .Chart.Name .Values.nameOverride -}}
        {{- if contains $name .Release.Name -}}
            {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
        {{- else -}}
            {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
        {{- end -}}
    {{- end -}}
{{- end -}}

{{/*
    Create chart name and version as used by the chart label.
*/}}
{{- define "web-app-serve.chart" -}}
    {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the proper image name with tag
*/}}
{{- define "web-app-serve.container_image" -}}
{{- $imageName := required ".Values.image.name" .Values.image.name -}}
{{- $imageTag := required ".Values.image.tag" .Values.image.tag -}}
{{- printf "%s:%s" $imageName $imageTag -}}
{{- end -}}

{{/*
Extract platform, repo, and image name from image repository and return as labels
Usage: {{ include "web-app-serve.ingress_project_labels" . }}
*/}}
{{- define "web-app-serve.ingress_project_labels" -}}
{{- $image := .Values.image.name | default "" -}}
{{- $parts := splitList "/" $image -}}

{{- $registry := (index $parts 0) | default "" -}}
{{- $org := (index $parts 1) | default "" -}}

{{- $imageNameParts := list -}}
{{- range $i, $val := $parts }}
  {{- if ge (int $i) 2 }}
    {{- $imageNameParts = append $imageNameParts $val }}
  {{- end }}
{{- end }}

{{- $imageName := join "/" $imageNameParts -}}

{{- $tagRaw := .Values.image.tag -}}
{{- $tagRawList := splitList "" $tagRaw -}}
{{- $tagRawLength := len $tagRawList -}}

{{- $tagTruncated := "" -}}
{{- if lt $tagRawLength 63 -}}
  {{- $tagTruncated = $tagRaw -}}
{{- else -}}
  {{- $tagRawStart := sub $tagRawLength 63 -}}
  {{- $tagRawLast63Chars := slice $tagRawList $tagRawStart $tagRawLength -}}
  {{- $tagTruncated = join "" $tagRawLast63Chars -}}
{{- end -}}

web-app-serve/docker-registry: {{ $registry | quote }}
web-app-serve/docker-org: {{ $org | quote }}
web-app-serve/docker-name: {{ $imageName | quote }}
web-app-serve/docker-truncated-tag: {{ $tagTruncated | quote }}
{{- end }}
