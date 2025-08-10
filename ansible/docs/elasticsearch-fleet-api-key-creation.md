# Creating Elasticsearch API Keys for Fleet Agent Policy Management

This guide shows how to create API keys with the necessary privileges to manage Fleet agent policies in Kibana and create Fleet server service tokens.

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

## Ansible Integration

For Ansible playbooks, store the encoded API key in your vault and use it like this:

```yaml
- name: Create agent policy
  uri:
    url: "{{ kibana_url }}/api/fleet/agent_policies"
    method: POST
    headers:
      Content-Type: "application/json"
      kbn-xsrf: "true"
      Authorization: "ApiKey {{ fleet_manager_api_key }}"
    body_format: json
    body:
      name: "synthetic-monitor-policy"
      namespace: "default"
      description: "Default policy for synthetic monitoring"
    return_content: yes
    status_code: [200, 201, 409]
  register: create_policy
  failed_when: false

- name: Create Fleet server service token
  uri:
    url: "{{ elastic_endpoint }}/_security/service/elastic/fleet-server/credential/token/fleet-server-token-{{ ansible_date_time.epoch }}"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "ApiKey {{ fleet_manager_api_key }}"
    return_content: yes
    status_code: [200, 201]
  register: service_token_response

- name: Create Kubernetes secret
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
        FLEET_SERVER_SERVICE_TOKEN: "{{ service_token_response.json.token.value }}"
```

## Prerequisites for Ansible

Install the required Python library for Kubernetes operations:

```bash
# For pipx-managed Ansible
pipx inject ansible kubernetes

# Or for system-wide installation
pip3 install kubernetes --break-system-packages
```

## Troubleshooting

### Common Issues

1. **403 Forbidden Error**: The API key lacks proper privileges
   - **For Fleet policies**: Ensure `applications` section includes `kibana-.kibana` with `all` privileges
   - **For service tokens**: Ensure cluster privileges include `manage_service_account`

2. **409 Conflict Error**: Resource already exists
   - **Agent policies**: Use `status_code: [200, 201, 409]` and `failed_when: false` to continue
   - **Service tokens**: Use unique token names with timestamps

3. **400 Bad Request**: Invalid request body format
   - Check that `monitoring_enabled` field uses valid values: `["logs"]`, `["metrics"]`, `["traces"]`
   - Or omit the field entirely to disable monitoring

4. **401 Unauthorized**: Invalid or expired API key
   - Regenerate the API key using one of the methods above

5. **Kubernetes module not found**: Missing Python library
   - Install kubernetes library: `pipx inject ansible kubernetes`

### Verification

Test your API key by creating a test policy:

```bash
curl -X POST "https://your-kibana-url/api/fleet/agent_policies" \
  -H "Authorization: ApiKey YOUR_ENCODED_API_KEY" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-policy",
    "namespace": "default",
    "description": "Test policy"
  }'
```

## Security Notes

- Store API keys securely (use Ansible Vault, environment variables, or secret management systems)
- Rotate API keys regularly
- Use principle of least privilege - only grant necessary permissions
- Monitor API key usage through Elasticsearch logs
- Service tokens should be unique and rotated periodically

## References

- [Elasticsearch API Key Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/security-api-create-api-key.html)
- [Kibana Fleet API Documentation](https://www.elastic.co/guide/en/fleet/current/fleet-api-docs.html)
- [Kibana Security Privileges](https://www.elastic.co/guide/en/kibana/current/kibana-privileges.html)
- [Fleet Server Service Tokens](https://www.elastic.co/guide/en/fleet/current/fleet-server.html#fleet-server-service-tokens)

---

**Note**: Replace `your-elasticsearch-url`, `your-kibana-url`, `your-password`, and `YOUR_ENCODED_API_KEY` with your actual values.
