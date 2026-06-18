#!/usr/bin/env bash
set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LITELLM_KEY="${LITELLM_KEY:-sk-local-morpheus-001}"
MODEL_ALIAS="${MODEL_ALIAS:-local-llama}"
RAW_MODEL_NAME="${RAW_MODEL_NAME:-llama3.2:3b}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err() { echo -e "${RED}❌ $*${NC}"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
step() { echo -e "${MAGENTA}${BOLD}🧪 $*${NC}"; }
substep() { echo -e "${CYAN}➡️  $*${NC}"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Comando obrigatório não encontrado: $1"; exit 1; }
}

need_cmd curl
need_cmd grep
need_cmd sed
need_cmd tr

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HTTP_CODE=""
BODY_FILE=""
LAST_BODY=""

http_get() {
  local url="$1"
  local body_file="$2"
  shift 2 || true
  HTTP_CODE=$(curl -sS -m "$CURL_TIMEOUT" -o "$body_file" -w "%{http_code}" "$url" "$@")
  LAST_BODY="$body_file"
}

http_post_json() {
  local url="$1"
  local body_file="$2"
  local data="$3"
  shift 3 || true
  HTTP_CODE=$(curl -sS -m "$CURL_TIMEOUT" -o "$body_file" -w "%{http_code}" -X POST "$url" "$@" -H "Content-Type: application/json" -d "$data")
  LAST_BODY="$body_file"
}

print_body_snippet() {
  local file="$1"
  sed -n '1,60p' "$file"
}

extract_content() {
  local file="$1"
  sed -n 's/.*"content":"\([^"]*\)".*/\1/p' "$file" | sed 's/\\n/ /g' | sed 's/\\"/"/g' | head -n 1
}

contains_any() {
  local text="$1"
  shift
  local norm
  norm=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  for token in "$@"; do
    if echo "$norm" | grep -qi "$token"; then
      return 0
    fi
  done
  return 1
}

TOTAL_TESTS=0
FAILED_TESTS=0
WARN_TESTS=0

pass_test() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  ok "$1"
}

fail_test() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  FAILED_TESTS=$((FAILED_TESTS + 1))
  err "$1"
}

warn_test() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  WARN_TESTS=$((WARN_TESTS + 1))
  warn "$1"
}

step "Iniciando validação do ambiente Ollama + LiteLLM"
info "Ollama URL   : $OLLAMA_URL"
info "LiteLLM URL  : $LITELLM_URL"
info "Modelo bruto : $RAW_MODEL_NAME"
info "Alias modelo : $MODEL_ALIAS"

step "Teste 1 - Verificando se a API do Ollama está acessível"
BODY_FILE="$TMP_DIR/ollama_tags.json"
if http_get "$OLLAMA_URL/api/tags" "$BODY_FILE"; then
  if [[ "$HTTP_CODE" == "200" ]]; then
    pass_test "A API do Ollama respondeu com HTTP 200 em /api/tags."
    if grep -q "$RAW_MODEL_NAME" "$BODY_FILE"; then
      pass_test "O modelo '$RAW_MODEL_NAME' foi encontrado no Ollama."
    else
      warn_test "A API do Ollama respondeu, mas o modelo '$RAW_MODEL_NAME' não apareceu em /api/tags."
      substep "Trecho da resposta do Ollama:"
      print_body_snippet "$BODY_FILE"
    fi
  else
    fail_test "A API do Ollama respondeu com HTTP $HTTP_CODE em /api/tags."
    print_body_snippet "$BODY_FILE"
  fi
else
  fail_test "Não foi possível conectar ao Ollama em $OLLAMA_URL."
fi

step "Teste 2 - Verificando se o LiteLLM está autenticando e listando modelos"
BODY_FILE="$TMP_DIR/litellm_models.json"
if http_get "$LITELLM_URL/v1/models" "$BODY_FILE" -H "Authorization: Bearer $LITELLM_KEY"; then
  if [[ "$HTTP_CODE" == "200" ]]; then
    pass_test "O LiteLLM respondeu com HTTP 200 em /v1/models usando a API Key informada."
    if grep -q "$MODEL_ALIAS" "$BODY_FILE"; then
      pass_test "O alias '$MODEL_ALIAS' foi encontrado no LiteLLM."
    else
      warn_test "O LiteLLM respondeu, mas o alias '$MODEL_ALIAS' não apareceu em /v1/models."
      substep "Trecho da resposta do LiteLLM:"
      print_body_snippet "$BODY_FILE"
    fi
  elif [[ "$HTTP_CODE" == "401" ]]; then
    fail_test "O LiteLLM rejeitou a autenticação. Verifique a LITELLM_MASTER_KEY e o header Bearer."
    print_body_snippet "$BODY_FILE"
  else
    fail_test "O LiteLLM respondeu com HTTP $HTTP_CODE em /v1/models."
    print_body_snippet "$BODY_FILE"
  fi
else
  fail_test "Não foi possível conectar ao LiteLLM em $LITELLM_URL."
fi

step "Teste 3 - Verificando geração simples no LiteLLM com o modelo '$MODEL_ALIAS'"
BODY_FILE="$TMP_DIR/litellm_chat_simple.json"
read -r -d '' PAYLOAD_SIMPLE <<JSON || true
{
  "model": "$MODEL_ALIAS",
  "messages": [
    {"role": "user", "content": "Responda apenas com a frase: teste local ok"}
  ]
}
JSON

if http_post_json "$LITELLM_URL/v1/chat/completions" "$BODY_FILE" "$PAYLOAD_SIMPLE" -H "Authorization: Bearer $LITELLM_KEY"; then
  if [[ "$HTTP_CODE" == "200" ]]; then
    SIMPLE_CONTENT="$(extract_content "$BODY_FILE")"
    pass_test "O LiteLLM retornou resposta para um prompt simples."
    substep "Resposta recebida: ${BOLD}${SIMPLE_CONTENT:-<vazia>} ${NC}"
    if contains_any "$SIMPLE_CONTENT" "teste local ok" "local ok"; then
      pass_test "O modelo seguiu parcialmente ou totalmente a instrução do prompt simples."
    else
      warn_test "O modelo respondeu, mas não repetiu exatamente a frase esperada. Isso pode acontecer em modelos menores."
    fi
  else
    fail_test "O endpoint /v1/chat/completions respondeu com HTTP $HTTP_CODE no prompt simples."
    print_body_snippet "$BODY_FILE"
  fi
else
  fail_test "Falha ao chamar /v1/chat/completions no teste simples."
fi

step "Teste 4 - Verificando compreensão semântica do modelo com uma pergunta factual"
BODY_FILE="$TMP_DIR/litellm_chat_semantic.json"
read -r -d '' PAYLOAD_SEMANTIC <<JSON || true
{
  "model": "$MODEL_ALIAS",
  "messages": [
    {"role": "user", "content": "Qual é a capital do Brasil? Responda em uma frase curta."}
  ]
}
JSON

if http_post_json "$LITELLM_URL/v1/chat/completions" "$BODY_FILE" "$PAYLOAD_SEMANTIC" -H "Authorization: Bearer $LITELLM_KEY"; then
  if [[ "$HTTP_CODE" == "200" ]]; then
    SEM_CONTENT="$(extract_content "$BODY_FILE")"
    substep "Resposta recebida: ${BOLD}${SEM_CONTENT:-<vazia>} ${NC}"
    if contains_any "$SEM_CONTENT" "brasilia" "brasília"; then
      pass_test "O modelo demonstrou compreensão básica e respondeu corretamente à pergunta factual."
    else
      fail_test "O modelo respondeu, mas a resposta factual não parece correta para a pergunta sobre a capital do Brasil."
      substep "Resposta completa para análise:"
      print_body_snippet "$BODY_FILE"
    fi
  else
    fail_test "O endpoint /v1/chat/completions respondeu com HTTP $HTTP_CODE no teste semântico."
    print_body_snippet "$BODY_FILE"
  fi
else
  fail_test "Falha ao chamar /v1/chat/completions no teste semântico."
fi

echo
step "Resumo final da validação"
info "Total de verificações : $TOTAL_TESTS"
info "Falhas                : $FAILED_TESTS"
info "Alertas               : $WARN_TESTS"

if [[ "$FAILED_TESTS" -eq 0 ]]; then
  ok "Resultado final: ambiente funcional. LiteLLM e Ollama responderam corretamente."
  if [[ "$WARN_TESTS" -gt 0 ]]; then
    warn "Existem alertas de comportamento, mas a integração base está operacional."
  fi
  info "Próximo passo sugerido: testar a integração no Morpheus com o endpoint ${LITELLM_URL}/v1 e a API Key configurada."
  exit 0
else
  err "Resultado final: houve falhas que precisam ser corrigidas antes da integração com o Morpheus."
  exit 1
fi