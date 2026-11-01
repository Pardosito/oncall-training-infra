import {
  AppsV1Api,
  CoreV1Api,
  KubeConfig,
  PatchStrategy,
  setHeaderOptions,
} from "@kubernetes/client-node";
import type { MockDeployment } from "./fault.js";

// The only module that talks to Kubernetes (CONVENTIONS §4). Every call is namespaced, and
// uses only what Role `mock-injector` allows (ARCHITECTURE §5.2):
// get/list/delete pods, get/patch deployments and deployments/scale.

export interface MockCluster {
  scaleToZero(deployment: MockDeployment): Promise<void>;
  /** Deletes the deployment's pods; returns how many were deleted. */
  deletePods(deployment: MockDeployment): Promise<number>;
}

export function createMockCluster(namespace: string, kubeConfig?: KubeConfig): MockCluster {
  const kc = kubeConfig ?? new KubeConfig();
  if (!kubeConfig) kc.loadFromDefault(); // in-cluster service account, or ~/.kube/config locally
  const apps = kc.makeApiClient(AppsV1Api);
  const core = kc.makeApiClient(CoreV1Api);

  return {
    async scaleToZero(deployment) {
      await apps.patchNamespacedDeploymentScale(
        { name: deployment, namespace, body: { spec: { replicas: 0 } } },
        // The generated client defaults to JSON Patch; a plain object body needs merge patch.
        setHeaderOptions("Content-Type", PatchStrategy.MergePatch),
      );
    },

    async deletePods(deployment) {
      // No `deletecollection` in the Role: list by label, then delete one by one.
      const pods = await core.listNamespacedPod({
        namespace,
        labelSelector: `app.kubernetes.io/name=${deployment}`,
      });
      const names = pods.items.flatMap((p) => (p.metadata?.name ? [p.metadata.name] : []));
      await Promise.all(names.map((name) => core.deleteNamespacedPod({ name, namespace })));
      return names.length;
    },
  };
}
