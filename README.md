## ingress-controller-domain-hack

Currently there is no way when using Ingress Controller sharding for the IC.spec.domain to be automatically attached to your generated Route hostname.

Host is currently set based on the cluster setting in `ingress.config` and / or `spec.appsDomain` if set in that object.

```
oc get ingress.config/cluster --template '{{.spec.domain}}'
```

See the [RFE](https://issues.redhat.com/browse/RFE-2248)

### Proof of concept

We can write automation that allows us to create Routes by:

- observing openshift api for Route addditions
- check whether `Route.spec.host` matched the expected `IngressController.spec.domain` that exposes the Route
- if it does not match, recreate the `Route` with the correct `host` set.

### Setup

- OpenShift 4.X cluster

Create an Ingress Controller shard called `redhatlabs` based on a label selector

```bash
oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: redhatlabs
  namespace: openshift-ingress-operator
spec:
  domain: redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev
  endpointPublishingStrategy:
    type: LoadBalancerService
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
  namespaceSelector:
    matchExpressions:
    - key: type
      operator: In
      values:
      - redhatlabs
status: {}
EOF
```

Patch the default IC shard so Routes are not exposed here with the `redhatlabs` label

```bash
oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p \
 '{
    "spec": {
      "namespaceSelector": {
          "matchExpressions": [
              {
                  "key": "type",
                  "operator": "NotIn",
                  "values": [
                      "redhatlabs"
                  ]
              }
          ]
       }
     }
  }'
```

Create a project to test with and label it

```bash
oc new-project test-ingress-welcome
oc label --overwrite namespace test-ingress-welcome type=redhatlabs
```

### Deploy Test Application

Deploy a hello world app

```bash
oc new-app quay.io/eformat/welcome
oc expose svc welcome --name=welcome
oc patch route/welcome --type=json -p '[{"op":"add", "path":"/spec/tls", "value":{"termination":"edge","insecureEdgeTerminationPolicy":"Redirect"}}]'
```

Check the route details including the hostname and router it is exposed on

```bash
# check default domain
oc get ingress.config/cluster --template '{{.spec.domain}}' 
apps.openshift-4815-njnfd.do500.redhatlabs.dev

# check route
oc get route welcome --template='{{ .spec.host }}'
welcome-test-ingress-welcome.apps.openshift-4815-njnfd.do500.redhatlabs.dev

# check the router name the route is exposed on
oc get route welcome -o jsonpath='{ .status.ingress[0].routerName }'
redhatlabs
```

So, we can see the host does not match the `IngressController.spec.domain` which is "redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev"

Delete the Route before the next step

```bash
oc delete route welcome
```

### Now run the PoC script

Run the script as follows, it will print out all the Routes in the cluster.

```bash
oc observe routes --type-env-var=T --all-namespaces -- route.pl
```

Create the new welcome Route again

```bash
oc expose svc welcome --name=welcome
```

Output shows the Route being observed with the wrong domain, then recreated with the correct domain based on IC

```bash
# 2021-11-10T08:30:43+10:00 Sync ended
# 2021-11-10T08:30:43+10:00 Added 16572797	route.pl test-ingress-welcome welcome ""
>> EXPECTED host: welcome-test-ingress-welcome.apps.openshift-4815-njnfd.do500.redhatlabs.dev does not match router domain: redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev
# 2021-11-10T08:30:48+10:00 Updated 16572799	route.pl test-ingress-welcome welcome ""
# 2021-11-10T08:30:48+10:00 Added 16572902	route.pl test-ingress-welcome welcome ""
>> OK added host welcome-test-ingress-welcome.redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev matches expected router domain: redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev
# 2021-11-10T08:30:50+10:00 Updated 16572904	route.pl test-ingress-welcome welcome ""
```

and now we get `redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev` as per IC

```bash
# check route
oc get route welcome --template='{{ .spec.host }}'
welcome-test-ingress-welcome.redhatlabs.apps.openshift-4815-njnfd.do500.redhatlabs.dev
```

### Further work

This poc could be made more concrete by implementing as:

- a Pod that runs on the cluster
- a Mutating WebHook
- an Operator

This script does not handle edge cases, its a Poc ! Some more complex use cases could include:

- `redhatlabs` IC is hardcoded, could discover this list
- does not check for `Ingress`, only Routes
- error handling
