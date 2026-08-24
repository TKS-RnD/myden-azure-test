#!/bin/bash

# Function to request certificate using acme.sh
function request_certificate() {
  local domain=$1
  local days=$2
  local email=$3
  echo "Requesting certificate for ${domain} and *.${domain} with renewal threshold of ${days} days using email ${email}..."

  # Register account with email if not already registered
  ~/.acme.sh/acme.sh --register-account -m "${email}" --server letsencrypt --syslog 0


  # Assume that AZUREDNS_SUBSCRIPTIONID and AZUREDNS_TENANTID are already set.
  # As per documentation, we need a bearer token approach for CI/CD workflow
  # See https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_azure
  if [[ ! -z "${AZUREDNS_SUBSCRIPTIONID}" ]] && [[ ! -z "${AZUREDNS_TENANTID}" ]]; then
    echo "Azure subscription and tenant IDs are set. Getting bearer token.."
    AZUREDNS_BEARERTOKEN=$(az account get-access-token --query accessToken --output tsv)
    export AZUREDNS_BEARERTOKEN
  fi

  ~/.acme.sh/acme.sh --issue --dns dns_azure                             \
                     --server letsencrypt --syslog 0 --days "${days}"    \
                     -d "${domain}" -d "*.${domain}"
}

# Function to import certificate to Azure Key Vault
function import_certificate() {
  local domain=$1
  local kv_name=$2
  local cert_name=$3

  echo "Converting certificate for $domain to PFX..."
  openssl pkcs12 -export                                        \
                -out cert.pfx                                   \
                -inkey "$HOME/.acme.sh/${domain}_ecc/${domain}.key" \
                -in "$HOME/.acme.sh/${domain}_ecc/fullchain.cer"    \
                -passout pass:

  echo "Importing cert.pfx to Key Vault ${kv_name} as ${cert_name}..."
  az keyvault certificate import --vault-name "${kv_name}" --name "${cert_name}" --file cert.pfx
}

# Main entry point
function main() {
  local domain=""
  local kv_name=""
  local cert_name=""
  local email=""
  local expiry_days=30

  while [[ $# -gt 0 ]]; do
    case $1 in
      --domain) domain="$2"; shift 2 ;;
      --vault) kv_name="$2"; shift 2 ;;
      --name) cert_name="$2"; shift 2 ;;
      --email) email="$2"; shift 2 ;;
      --expiry) expiry_days="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "${domain}" || -z "${kv_name}" || -z "${cert_name}" || -z "${email}" ]]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 --domain <domain> --vault <keyvault> --name <name> --email <email> [--expiry <days>]"
    exit 1
  fi

  request_certificate "${domain}" "${expiry_days}" "${email}"
  import_certificate "${domain}" "${kv_name}" "${cert_name}"
}

# Execute main function with all arguments
main "$@"
