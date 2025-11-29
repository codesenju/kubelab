# Creating Elasticsearch API Keys for Fleet Agent Policy Management

This guide shows how to create API keys with the necessary privileges to manage Fleet agent policies in Kibana, create Fleet server service tokens, and deploy Fleet agents including synthetic monitors.

## Required Privileges

The API key needs these privileges:
- **Elasticsearch cluster**: `manage`, `manage_api_key`, `manage_service_account`
- **Elasticsearch indices**: `all` on `.fleet*`, `.kibana*`, `logs-*`, `metrics-*`
- **Kibana application**: `all` privileges on `kibana-.kibana`

## Method 1: Using Kibana Dashboard

1. Navigate to **Stack Management** → **API Keys**
2. Click **Create API Key**
3. Set name: `fleet-manager`
4. Under **Role descriptors**, add:
```json
{
  "fleet_admin": {
    "cluster": ["manage", "manage_api_key", "manage_service_account"],
    "indices": [
      {
        "names": [".fleet*", ".kibana*", "logs-*", "metrics-*"],
        "privileges": ["all"],
        "allow_restricted_indices": true
      }
    ],
    "applications": [
      {
        "application": "kibana-.kibana",
        "privileges": ["all"],
        "resources": ["*"]
      }
    ]
  }
}
```
5. Click **Create API Key**
6. Copy the **Encoded** value for use in your applications

## Method 2: Using Kibana Dev Tools

1. Go to **Dev Tools** → **Console**
2. Run this command:
```json
POST /_security/api_key
{
  "name": "fleet-manager",
  "role_descriptors": {
    "fleet_admin": {
      "cluster": ["manage", "manage_api_key", "manage_service_account"],
      "indices": [
        {
          "names": [".fleet*", ".kibana*", "logs-*", "metrics-*"],
          "privileges": ["all"],
          "allow_restricted_indices": true
        }
      ],
      "applications": [
        {
          "application": "kibana-.kibana",
          "privileges": ["all"],
          "resources": ["*"]
        }
      ]
    }
  }
}
```
3. Copy the `encoded` value from the response

## Method 3: Using cURL

```bash
curl -X POST "https://your-elasticsearch-url/_security/api_key" \
  -u "elastic:your-password" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "fleet-manager",
    "role_descriptors": {
      "fleet_admin": {
        "cluster": ["manage", "manage_api_key", "manage_service_account"],
        "indices": [
          {
            "names": [".fleet*", ".kibana*", "logs-*", "metrics-*"],
            "privileges": ["all"],
            "allow_restricted_indices": true
          }
        ],
        "applications": [
          {
            "application": "kibana-.kibana",
            "privileges": ["all"],
            "resources": ["*"]
          }
        ]
      }
    }
  }'
```

## Fleet Server Setup

### Complete Fleet Server Deployment

The Fleet Server setup includes creating a policy with Fleet Server integration, service tokens, and Kubernetes secrets:

```yaml
# Fleet Server Policy with Integration
- name: Create fleet server policy
  uri:
    url: "{{ kibana_url }}/api/fleet/agent_policies"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      name: "fleet-server-policy-default"
      namespace: "default"
      description: "Default Fleet Server policy"

# Add Fleet Server Integration
- name: Add Fleet Server integration
  uri:
    url: "{{ kibana_url }}/api/fleet/package_policies"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      name: "fleet_server-default-policy"
      namespace: "default"
      policy_id: "{{ agent_policy_id }}"
      enabled: true
      package:
        name: "fleet_server"
        version: "1.6.0"
      inputs:
        - type: "fleet-server"
          enabled: true
          streams: []
          vars:
            host:
              value: ["0.0.0.0:8220"]
              type: "text"
            port:
              value: [8220]
              type: "integer"

# Create Fleet Server Host
- name: Add Fleet Server host
  uri:
    url: "{{ kibana_url }}/api/fleet/fleet_server_hosts"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      name: "elastic-fleet-server-default"
      host_urls: ["{{ fleet_server_default_url }}"]
      is_default: true

# Create Service Token
- name: Create Fleet server service token
  uri:
    url: "{{ elastic_endpoint }}/_security/service/elastic/fleet-server/credential/token/fleet-server-token-{{ ansible_date_time.epoch }}"
    method: POST
    headers: "{{ es_headers }}"

# Create Kubernetes Secret
- name: Create fleet-server-config secret
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: fleet-server-config
        namespace: elastic-system
      type: Opaque
      stringData:
        FLEET_SERVER_ENABLE: "true"
        FLEET_SERVER_ELASTICSEARCH_HOST: "{{ elastic_endpoint }}"
        FLEET_SERVER_SERVICE_TOKEN: "{{ fleet_service_token }}"
```

## Synthetic Monitor Agent Setup

### Creating Synthetic Monitor Agent Policy with Private Location

Create a policy for synthetic monitoring agents with no integrations and set up a private location:

```yaml
# Create Synthetic Monitor Policy (No Integrations)
- name: Create synthetic monitor agent policy
  uri:
    url: "{{ kibana_url }}/api/fleet/agent_policies"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      name: "synthetic-monitor-policy-default"
      namespace: "default"
      description: "Policy for Elastic Synthetic Monitor agents"

# Create Synthetic Private Location
- name: Create synthetic private location
  uri:
    url: "{{ kibana_url }}/api/synthetics/private_locations"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      label: "synthetic-monitor-default"
      agentPolicyId: "{{ agent_policy_id }}"
      tags: ["default", "private"]
      geo:
        lat: 40.7128
        lon: -74.0060

# Generate Enrollment Token
- name: Get enrollment token for the policy
  uri:
    url: "{{ kibana_url }}/api/fleet/enrollment_api_keys"
    method: POST
    headers: "{{ kbn_headers }}"
    body_format: json
    body:
      name: "synthetic-monitor-enrollment-{{ ansible_date_time.epoch }}"
      policy_id: "{{ agent_policy_id }}"

# Create Agent Configuration Secret
- name: Create synthetic-monitor-config secret
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: synthetic-monitor-config
        namespace: elastic-system
      type: Opaque
      stringData:
        FLEET_URL: "{{ fleet_server_default_url }}"
        FLEET_ENROLLMENT_TOKEN: "{{ enrollment_token }}"
        FLEET_ENROLL: "1"
        FLEET_INSECURE: "false"

# Deploy via ArgoCD
- name: Create ArgoCD Application
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: elastic-synthetic-monitor
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: "https://github.com/codesenju/kubelab.git"
          targetRevision: HEAD
          path: kustomize/elastic-synthetic-monitor/overlays/prod
        destination:
          server: https://kubernetes.default.svc
          namespace: elastic-system
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
```

## Usage Examples

### Create Agent Policy

```bash
curl -X POST "https://your-kibana-url/api/fleet/agent_policies" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-policy",
    "namespace": "default",
    "description": "My agent policy"
  }'
```

### Create Fleet Server Service Token

```bash
curl -X POST "https://your-elasticsearch-url/_security/service/elastic/fleet-server/credential/token/my-token-name" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY"
```

### Create Fleet Server Host

```bash
curl -X POST "https://your-kibana-url/api/fleet/fleet_server_hosts" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-fleet-server",
    "host_urls": ["https://fleet-server.example.com:443"],
    "is_default": true
  }'
```

### Create Synthetic Private Location

```bash
curl -X POST "https://your-kibana-url/api/synthetics/private_locations" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "my-private-location",
    "agentPolicyId": "your-policy-id",
    "tags": ["production", "private"],
    "geo": {
      "lat": 40.7128,
      "lon": -74.0060
    }
  }'
```

### Generate Enrollment Token

```bash
curl -X POST "https://your-kibana-url/api/fleet/enrollment_api_keys" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-enrollment-token",
    "policy_id": "your-policy-id"
  }'
```

## Ansible Playbook Examples

### Fleet Server Playbook (`elastic-fleet.yaml`)

Complete Fleet Server setup with policy, integration, host, and service token:

```yaml
- name: Create Kibana Fleet Agent Policy and Kubernetes Secret
  hosts: localhost
  connection: local
  gather_facts: true
  vars:
    kbn_headers:
      Content-Type: "application/json"
      kbn-xsrf: "true"
      Authorization: "ApiKey {{ fleet_manager_api_key }}"
    es_headers:
      Content-Type: "application/json"
      Authorization: "ApiKey {{ fleet_manager_api_key }}"

  tasks:
    # Create policy, integration, host, service token, and Kubernetes secret
    # (See complete example in repository)
```

### Synthetic Monitor Playbook (`elastic-synthetic-monitor.yaml`)

Complete synthetic monitor agent setup with policy, private location, enrollment, and ArgoCD deployment:

```yaml
- name: Create Elastic Synthetic Monitor Agent Policy and ArgoCD Application
  hosts: localhost
  connection: local
  gather_facts: true
  vars:
    kbn_headers:
      Content-Type: "application/json"
      kbn-xsrf: "true"
      Authorization: "ApiKey {{ fleet_manager_api_key }}"
    synthetic_monitor_policy_name: "synthetic-monitor-policy-default"

  tasks:
    # Create policy
    - name: Create synthetic monitor agent policy
      uri:
        url: "{{ kibana_url }}/api/fleet/agent_policies"
        method: POST
        headers: "{{ kbn_headers }}"
        body_format: json
        body:
          name: "{{ synthetic_monitor_policy_name }}"
          namespace: "default"
          description: "Policy for Elastic Synthetic Monitor agents"

    # Create private location
    - name: Create synthetic private location
      uri:
        url: "{{ kibana_url }}/api/synthetics/private_locations"
        method: POST
        headers: "{{ kbn_headers }}"
        body_format: json
        body:
          label: "synthetic-monitor-default"
          agentPolicyId: "{{ agent_policy_id }}"
          tags: ["default", "private"]
          geo:
            lat: 40.7128
            lon: -74.0060

    # Generate enrollment token, create secrets, and deploy via ArgoCD
    # (See complete example in repository)
```

## Consolidated Playbook Approach

### Single Playbook for Complete Setup

The `elastic-synthetic-monitor.yaml` playbook now handles the complete synthetic monitoring setup in a single execution:

1. **Agent Policy Creation**: Creates `synthetic-monitor-policy-default`
2. **Private Location Setup**: Creates `synthetic-monitor-default` private location
3. **Token Generation**: Creates dynamic enrollment tokens
4. **Secret Management**: Creates Kubernetes secrets with Fleet configuration
5. **ArgoCD Deployment**: Deploys the synthetic monitor application

### Benefits of Consolidated Approach

- **Simplified Execution**: Single command deploys entire stack
- **Dependency Management**: Ensures proper order of resource creation
- **Error Handling**: Graceful handling of existing resources
- **Consistency**: Uses consistent naming and configuration across components

### Playbook Structure

```yaml
vars:
  synthetic_monitor_policy_name: "synthetic-monitor-policy-default"

tasks:
  1. Create/verify agent policy
  2. Create synthetic private location
  3. Generate enrollment token
  4. Create Kubernetes secrets
  5. Deploy ArgoCD application
```

## Prerequisites for Ansible

Install the required Python library for Kubernetes operations:

```bash
# For pipx-managed Ansible
pipx inject ansible kubernetes

# Or for system-wide installation
pip3 install kubernetes --break-system-packages
```

## Configuration Variables

Add these variables to your Ansible vault (`group_vars/all/secrets.yaml`):

```yaml
# API Key for Fleet management
fleet_manager_api_key: "YOUR_ENCODED_API_KEY"

# Fleet Server URL
fleet_server_default_url: "https://elastic-fleet.local.example.com:443"

# Kibana URL
kibana_url: "https://kibana.local.example.com"

# Elasticsearch URL
elastic_endpoint: "https://es.local.example.com"

# Gitea instance URL (for ArgoCD)
gitea_instance_url: "https://git.example.com"
```

## Deployment Architecture

### Fleet Server Components
1. **Agent Policy**: `fleet-server-policy-default`
2. **Fleet Server Integration**: `fleet_server-default-policy`
3. **Fleet Server Host**: `elastic-fleet-server-default`
4. **Service Token**: For Fleet Server authentication
5. **Kubernetes Secret**: `fleet-server-config`

### Synthetic Monitor Components
1. **Agent Policy**: `synthetic-monitor-policy-default` (no integrations)
2. **Private Location**: `synthetic-monitor-default` (linked to agent policy)
3. **Enrollment Token**: Dynamic token for agent enrollment
4. **Kubernetes Secret**: `synthetic-monitor-config`
5. **ArgoCD Application**: `elastic-synthetic-monitor`

## Troubleshooting

### Common Issues

1. **403 Forbidden Error**: The API key lacks proper privileges
   - **For Fleet policies**: Ensure `applications` section includes `kibana-.kibana` with `all` privileges
   - **For service tokens**: Ensure cluster privileges include `manage_service_account`

2. **409 Conflict Error**: Resource already exists
   - **Agent policies**: Use `status_code: [200, 201, 409]` and `failed_when: false` to continue
   - **Service tokens**: Use unique token names with timestamps
   - **Integration names**: Use unique names like `fleet_server-default-policy`

3. **400 Bad Request**: Invalid request body format
   - Check Fleet Server package version (use `1.6.0` instead of `1.7.0`)
   - Verify integration configuration parameters

4. **401 Unauthorized**: Invalid or expired API key
   - Regenerate the API key using one of the methods above

5. **Kubernetes module not found**: Missing Python library
   - Install kubernetes library: `pipx inject ansible kubernetes`

7. **Private location policy mismatch**: Private location using wrong agent policy
   - Delete existing private location and recreate with correct policy ID
   - Verify policy ID matches the intended policy name

8. **Private location creation fails**: Invalid agent policy ID
   - Ensure the agent policy exists before creating private location
   - Check that the policy ID is correct and accessible

6. **ArgoCD sync issues**: Git authentication required
   - Configure Git credentials in ArgoCD for private repositories

### Verification Commands

**Check Fleet Server host:**
```bash
curl -X GET "https://your-kibana-url/api/fleet/fleet_server_hosts" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true"
```

**Check synthetic private locations:**
```bash
curl -X GET "https://your-kibana-url/api/synthetics/private_locations" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true"
```

**Check agent policies:**
```bash
curl -X GET "https://your-kibana-url/api/fleet/agent_policies" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true"
```

**Check package policies (integrations):**
```bash
curl -X GET "https://your-kibana-url/api/fleet/package_policies" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true"
```

**Verify Kubernetes secrets:**
```bash
kubectl get secrets -n elastic-system | grep -E "(fleet-server-config|synthetic-monitor-config)"
```

**Check ArgoCD applications:**
```bash
kubectl get applications -n argocd
```

## Security Notes

- Store API keys securely (use Ansible Vault, environment variables, or secret management systems)
- Rotate API keys and service tokens regularly
- Use principle of least privilege - only grant necessary permissions
- Monitor API key usage through Elasticsearch logs
- Service tokens should be unique and rotated periodically
- Use TLS/SSL for all Fleet Server communications (`FLEET_INSECURE: "false"`)

## References

- [Elasticsearch API Key Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/security-api-create-api-key.html)
- [Kibana Fleet API Documentation](https://www.elastic.co/guide/en/fleet/current/fleet-api-docs.html)
- [Kibana Security Privileges](https://www.elastic.co/guide/en/kibana/current/kibana-privileges.html)
- [Fleet Server Service Tokens](https://www.elastic.co/guide/en/fleet/current/fleet-server.html#fleet-server-service-tokens)
- [Elastic Agent Synthetic Monitoring](https://www.elastic.co/guide/en/observability/current/synthetic-monitoring.html)
- [ArgoCD Application Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)

---

**Note**: Replace `your-elasticsearch-url`, `your-kibana-url`, `your-password`, and `YOUR_ENCODED_API_KEY` with your actual values.
