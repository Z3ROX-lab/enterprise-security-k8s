#!/bin/bash

echo "======================================"
echo "Security Stack Diagnostic Tool"
echo "======================================"
echo ""

echo "📊 CLUSTER STATUS"
echo "=================="
kubectl get nodes
echo ""

echo "💾 RESOURCE USAGE"
echo "=================="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""

echo "🔍 PODS STATUS - security-iam"
echo "=============================="
kubectl get pods -n security-iam 2>/dev/null || echo "Namespace not found"
echo ""

echo "🔍 PODS STATUS - security-detection"
echo "===================================="
kubectl get pods -n security-detection 2>/dev/null || echo "Namespace not found"
echo ""

echo "🔍 PODS STATUS - cert-manager"
echo "=============================="
kubectl get pods -n cert-manager 2>/dev/null || echo "Namespace not found"
echo ""

echo "❌ PODS IN ERROR STATE"
echo "======================"
kubectl get pods --all-namespaces | grep -E "Error|CrashLoop|Pending|ImagePull" || echo "No pods in error state"
echo ""

echo "📋 RECENT EVENTS (Last 10)"
echo "=========================="
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
echo ""

echo "🔧 HELM RELEASES"
echo "================"
helm list --all-namespaces
echo ""

echo "💡 FAILED PODS DETAILS"
echo "======================"
for ns in security-iam security-detection cert-manager; do
    echo "Namespace: $ns"
    for pod in $(kubectl get pods -n $ns 2>/dev/null | grep -E "Error|CrashLoop" | awk '{print $1}'); do
        echo "  Pod: $pod"
        kubectl describe pod $pod -n $ns | grep -A 5 "State:"
        echo "  Last 10 log lines:"
        kubectl logs $pod -n $ns --tail=10 2>&1 | sed 's/^/    /'
        echo ""
    done
done

echo "======================================"
echo "Diagnostic Complete"
echo "======================================"
