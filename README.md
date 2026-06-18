# Morpheus Data + LiteLLM + Ollama Local Integration

## Propósito

Este projeto habilita o uso local de uma solução de IA agêntica para o **Morpheus Data Enterprise 9.0.0**, usando um modelo local via **Ollama + Llama 3.2:3b**.

O **LiteLLM** atua como **gateway OpenAI-compatible** que expõe uma API `v1` compatível com a especificação **OpenAI Chat Completions API**, permitindo que o Morpheus Data consuma o backend local da mesma forma que consumiria um serviço de IA comercial.

```mermaid
flowchart TB
    subgraph Morpheus ["Morpheus Data Enterprise 9.0.0"]
        direction TB
        MCP["CMP (Cloud Management Platform)\n- Provisonamento multi-cloud\n- Automação DevOps / IaC\n- Orquestração de aplicações\n- FinOps e governança"]
        MAIA["IA Agêntica (Agentic AI)\n- Integração nativa com LLM\n- Espera endpoint OpenAI-compatible\n- Preenche: endpoint + API Key"]
        MCP --> MAIA
    end

    subgraph LiteLLM_Sub ["LiteLLM Proxy (AI Gateway)"]
        direction TB
        L_PROXY["Roteador de LLM\n(API OpenAI-compatible)\n- Traduz chamadas OpenAI\n- Expone /v1/chat/completions\n- Expone /v1/models"]
        L_GATEWAY["Gateway de IA\n(Roteamento, retries, fallbacks)\n- Auth com master key\n- Mapeia: local-llama → ollama/llama3.2:3b"]
        L_PROXY --> L_GATEWAY
    end

    subgraph Ollama_Sub ["Ollama (LLM Local)"]
        direction TB
        O_API["API do Ollama\n(nativa, não OpenAI)\n- /api/tags\n- /api/chat\n- /api/generate"]
        O_SRV["Servidor de Inferência\n(LLM local)\n- Executa o modelo\n- Gerencia GPU/CPU\n- Downloads de modelos"]
        O_API --> O_SRV
    end

    subgraph Modelo ["Modelo LLM"]
        direction TB
        LLAMA["Llama 3.2:3b\n(Meta)\n- Modelo de linguagem\n- Inferência local\n- Pequeno footprint\n- Adequado para teste"]
    end

    Morpheus -->|"HTTP /v1/chat/completions\nOpenAI-compatible\nAuthorization: Bearer sk-local-morpheus-001\nmodel: local-llama"| L_PROXY
    L_GATEWAY -->|"Roteia para Ollama\n(ollama/llama3.2:3b)\napi_base: http://ollama:11434"| O_API
    O_SRV -->|Gera resposta textual| LLAMA

    style Morpheus fill:#e3f2fd,stroke:#1976d2
    style LiteLLM_Sub fill:#fff3e0,stroke:#f57c00
    style Ollama_Sub fill:#e8f5e9,stroke:#388e3c
    style Modelo fill:#fce4ec,stroke:#c2185b
```

### O que ele entrega

- Um endpoint OpenAI-compatible local (`http://localhost:4000/v1`).
- Uma API Key estática usada pelo LiteLLM para autenticação.
- Um modelo local **Llama 3.2:3b** hospedado por **Ollama**.
- Um script de validação para testar a integração entre LiteLLM e Ollama.

## Arquivos principais

- `docker-compose.yaml` - define os serviços `ollama` e `litellm` e carrega variáveis automaticamente do `.env`.
- `.env-sample` - modelo de variáveis de ambiente para copiar em `.env`.
- `litellm_config.yaml.template` - template de configuração que é processado dinamicamente pelo container para gerar `config.yaml` baseado nas variáveis de `.env`.
- `test-litellm-ollama.sh` - script de validação do ambiente local.

## Pré-requisitos

- Docker e Docker Compose instalados.
- Conexão com a internet para fazer download do container Ollama e do modelo `llama3.2:3b` na primeira execução.
- Espaço de disco suficiente para o modelo local.

## Implantação local

1. Abra um terminal no diretório do projeto.
2. Copie o exemplo para `.env` (uma vez):

```bash
cp .env-sample .env
```

3. Inicie os serviços:

```bash
docker compose up -d
```

3. Verifique se os serviços estão rodando:

```bash
docker compose ps
```

4. Se necessário, acompanhe os logs:

```bash
docker compose logs -f
```

### O que acontece durante a inicialização

- O container `ollama` inicia o servidor Ollama.
- O entrypoint do `ollama` espera o serviço ficar pronto e, em seguida, verifica se o modelo definido em `OLLAMA_MODEL_NAME` está baixado.
- Se o modelo não existir, ele baixa automaticamente usando `ollama pull`.
- O container `litellm` inicia com um entrypoint que:
  1. Processa o template `litellm_config.yaml.template` usando variáveis do `.env`.
  2. Substitui `${LITELLM_MODEL_ALIAS}`, `${LITELLM_MODEL_REF}` e `${OLLAMA_URL}` pelos valores definidos em `.env`.
  3. Gera um `config.yaml` dinâmico.
  4. Inicia o LiteLLM com essa configuração.
- O LiteLLM expõe a API em `http://localhost:4000`.

## Teste do ambiente

Execute o script de validação local:

```bash
./test-litellm-ollama.sh
```

O script verifica:

- se a API do Ollama está acessível em `/api/tags`;
- se o LiteLLM responde em `/v1/models` usando a chave configurada;
- se o endpoint `/v1/chat/completions` gera respostas básicas e semânticas.

## Variáveis de ambiente usadas pelo `test-litellm-ollama.sh`

O script aceita as seguintes variáveis de ambiente para customizar o teste:

- `OLLAMA_URL` - URL base do Ollama (padrão: `http://localhost:11434`).
- `LITELLM_URL` - URL base do LiteLLM (padrão: `http://localhost:4000`).
- `LITELLM_KEY` - chave API usada para autenticar no LiteLLM (padrão: `sk-local-morpheus-001`).
- `MODEL_ALIAS` - alias de modelo configurado no `litellm_config.yaml` (padrão: `local-llama`).
- `RAW_MODEL_NAME` - nome do modelo esperado no Ollama (padrão: `llama3.2:3b`).
- `CURL_TIMEOUT` - timeout do `curl` usado pelo script (padrão: `30`).

Exemplo de uso:

```bash
OLLAMA_URL=http://localhost:11434 \
LITELLM_URL=http://localhost:4000 \
LITELLM_KEY=sk-local-morpheus-001 \
MODEL_ALIAS=local-llama \
RAW_MODEL_NAME=llama3.2:3b \
./test-litellm-ollama.sh
```

## Como trocar o modelo

### Alterar apenas o alias usado pelo teste

Ajuste `MODEL_ALIAS` e `RAW_MODEL_NAME` no comando de execução do script.

### Alterar o modelo servido pelo LiteLLM/Ollama

A configuração do modelo agora é controlada por variáveis no arquivo `.env`.

- `OLLAMA_MODEL_NAME` define o modelo que o Ollama deve baixar/usar.
- `LITELLM_MODEL_REF` define o modelo que o LiteLLM repassa para o Ollama.
- `LITELLM_MODEL_ALIAS` define o alias exposto pelo LiteLLM.

O `docker-compose.yaml` gera dinamicamente o `config.yaml` do LiteLLM a partir dessas variáveis.

Exemplo:

```env
OLLAMA_MODEL_NAME=llama3.2:3b
LITELLM_MODEL_REF=ollama/llama3.2:3b
LITELLM_MODEL_ALIAS=local-llama
```

## Como trocar a chave de API do LiteLLM

A chave do LiteLLM é definida no arquivo `.env` usando:

```env
LITELLM_MASTER_KEY=sk-local-morpheus-001
```

Basta alterar esse valor em `.env` e reiniciar os serviços.

No teste, use a mesma chave em `LITELLM_KEY`.

## Exemplo de uso com Morpheus Data

No Morpheus Data Enterprise 9.0.0, configure o endpoint de IA para o LiteLLM local:

- Endpoint: `http://localhost:4000/v1`
- API Key: `sk-local-morpheus-001`
- Modelo: `local-llama`

O Morpheus deve enviar requisições compatíveis com a API OpenAI Chat Completions, e o LiteLLM repassará essas requisições ao modelo Ollama local.

## Observações estratégicas

Este projeto é um teste de viabilidade para avaliar se o Morpheus Data consegue trabalhar com um backend local de IA em vez de serviços externos. Se funcionar, a abordagem pode ser útil para empresas que precisam de:

- menor dependência de provedores externos de IA;
- controle local de dados e inferências;
- governança e privacidade mais rígida;
- custo previsível sem uso de APIs comerciais.

## Dicas de validação

- Use `docker compose logs -f ollama` para ver a inicialização do Ollama.
- Use `docker compose logs -f litellm` para ver a inicialização do LiteLLM.
- Se o modelo não for baixado automaticamente, verifique a saída de `ollama list` dentro do container `ollama`.

## Comandos úteis

```bash
docker compose up -d

docker compose ps
docker compose logs -f

./test-litellm-ollama.sh
```
