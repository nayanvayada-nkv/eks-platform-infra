{{/* ECR registry prefix of this project, e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com/eks-platform/ */}}
{{- define "zt.registry" -}}
{{ required "awsAccountId is required" .Values.awsAccountId }}.dkr.ecr.{{ .Values.awsRegion }}.amazonaws.com/{{ .Values.project }}/
{{- end }}

{{/* Pod match rule shared by the pod policies: every namespace except the system ones. */}}
{{- define "zt.podMatch" -}}
matchConstraints:
  resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods]
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values:
          {{- toYaml .Values.systemNamespaces | nindent 10 }}
# Also check Deployments, StatefulSets, Jobs... so Argo CD shows the denial on the
# Deployment itself instead of a ReplicaSet silently failing to create pods.
autogen:
  podControllers:
    controllers: [deployments, statefulsets, daemonsets, jobs, cronjobs]
{{- end }}
