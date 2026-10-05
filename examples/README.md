# Examples

Manifests that use the OpenStack module images, as
[clusterctl](https://cluster-api.sigs.k8s.io/clusterctl/overview) templates:
`${VARIABLE}` and `${VARIABLE:=default}` are filled in by
`clusterctl generate yaml --from <file>`. Nothing here was applied to a
real cloud; [DESIGN.md](../DESIGN.md) "Unverified" lists what the first reviewed apply
must confirm.

| File | What it is | Applied by |
| --- | --- | --- |
| [`identity.yaml`](identity.yaml) | The credentials Secret (`OS_CLOUD`, `OS_CLIENT_CONFIG_FILE` and a `clouds.yaml` file key with an application credential) and the TerraformClusterIdentity | A cluster admin, once |
| [`cluster-kubeadm.yaml`](cluster-kubeadm.yaml) | A Cluster, its TerraformCluster, a KubeadmControlPlane and a MachineDeployment with their TerraformMachineTemplates, and MachineHealthChecks for both (2700 s and 3600 s) | Per cluster |
| [`cloud-controller-manager.yaml`](cloud-controller-manager.yaml) | The OpenStack cloud controller manager's `cloud.conf` and manifests, through a ClusterResourceSet | Per cluster |

The manifests pin every image to a release, `v0.1.0-opentofu`: change the
tag to the release you deploy (`vX.Y.Z-opentofu` or `vX.Y.Z-terraform`), or
to a digest. The moving tags (`opentofu`, `terraform`, `edge-<runtime>`) are
for trying things out, never for anything you keep.

Order:

1. `identity.yaml`, with `NAMESPACE`, `OPENSTACK_AUTH_URL`,
   `OPENSTACK_APPLICATION_CREDENTIAL_ID` and
   `OPENSTACK_APPLICATION_CREDENTIAL_SECRET`.
2. `cloud-controller-manager.yaml`, after creating the `openstack-ccm`
   ConfigMap its header describes, with a second, dedicated application
   credential.
3. `cluster-kubeadm.yaml`, with `CLUSTER_NAME`, `KUBERNETES_VERSION`,
   `OPENSTACK_SUBNET_ID`, `OPENSTACK_CONTROL_PLANE_FLAVOR`, `OPENSTACK_FLAVOR`
   and `OPENSTACK_IMAGE_NAME`.
4. A CNI, for example Calico, once the control plane answers.

Variables:

| Variable | Default | Used in | Meaning |
| --- | --- | --- | --- |
| `NAMESPACE` | | identity | Namespace allowed to use the identity |
| `OPENSTACK_IDENTITY_NAME` | `openstack` | identity, cluster | Name of the Secret and the TerraformClusterIdentity |
| `OPENSTACK_AUTH_URL` | | identity, controller manager | Keystone v3 URL |
| `OPENSTACK_APPLICATION_CREDENTIAL_ID`, `_SECRET` | | identity | Credential the modules run with |
| `OPENSTACK_CCM_APPLICATION_CREDENTIAL_ID`, `_SECRET` | | controller manager | Credential of the cloud controller manager |
| `OPENSTACK_REGION` | `RegionOne` | identity, controller manager | Region |
| `CLUSTER_NAME` | | cluster, controller manager | Cluster name |
| `KUBERNETES_VERSION` | | cluster | Kubernetes version of the image |
| `OPENSTACK_SUBNET_ID` | | cluster, controller manager | The existing subnet |
| `OPENSTACK_FLAVOR` | | cluster | Worker flavor |
| `OPENSTACK_CONTROL_PLANE_FLAVOR` | | cluster | Control-plane flavor |
| `OPENSTACK_IMAGE_NAME` | | cluster | Glance image with kubeadm `KUBERNETES_VERSION` |
| `CONTROL_PLANE_MACHINE_COUNT` | `3` | cluster | Control-plane replicas |
| `WORKER_MACHINE_COUNT` | `2` | cluster | Worker replicas |
| `POD_CIDR`, `SERVICE_CIDR` | `192.168.0.0/16`, `10.96.0.0/12` | cluster | Cluster networks |
