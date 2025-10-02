---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetria

Você pode ingerir métricas coletadas pelo servidor Tuist usando
[Prometheus](https://prometheus.io/) e uma ferramenta de visualização como
[Grafana](https://grafana.com/) para criar um painel personalizado adaptado às
suas necessidades. As métricas do Prometheus são servidas através do ponto final
`/metrics` na porta 9091. O
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
do Prometheus deve ser definido como inferior a 10_000 segundos (recomendamos
manter o padrão de 15 segundos).

## Análise PostHog {#posthog-analytics}

O Tuist integra-se com [PostHog](https://posthog.com/) para análise do
comportamento do utilizador e acompanhamento de eventos. Isto permite-lhe
compreender como os utilizadores interagem com o seu servidor Tuist, acompanhar
a utilização de funcionalidades e obter informações sobre o comportamento do
utilizador no site de marketing, painel de instrumentos e documentação API.

### Configuração {#posthog-configuration}

A integração do PostHog é opcional e pode ser activada definindo as variáveis de
ambiente apropriadas. Quando configurado, o Tuist irá rastrear automaticamente
os eventos do utilizador, as visualizações de página e as viagens do utilizador.

| Variável de ambiente    | Descrição                                       | Necessário | Predefinição | Exemplos                                          |
| ----------------------- | ----------------------------------------------- | ---------- | ------------ | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | A sua chave API do projeto PostHog              | Não        |              | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | O URL do ponto de extremidade da API do PostHog | Não        |              | `https://eu.i.posthog.com`                        |

> [A análise só é activada quando `TUIST_POSTHOG_API_KEY` e `TUIST_POSTHOG_URL`
> estão configurados. Se uma das variáveis estiver ausente, nenhum evento de
> análise será enviado.

### Caraterísticas {#posthog-features}

Quando o PostHog está ativado, o Tuist monitoriza automaticamente:

- **Identificação do utilizador**: Os utilizadores são identificados pelo seu ID
  único e endereço de correio eletrónico
- **Aliasing de utilizadores**: Os utilizadores são identificados pelo nome da
  sua conta para facilitar a identificação
- **Análises de grupo**: Os utilizadores são agrupados pelo projeto e
  organização selecionados para análises segmentadas
- **Secções da página**: Os eventos incluem super propriedades que indicam qual
  a secção da aplicação que os gerou:
  - `marketing` - Eventos de páginas de marketing e conteúdos públicos
  - `dashboard` - Eventos do dashboard principal da aplicação e das áreas
    autenticadas
  - `api-docs` - Eventos das páginas de documentação da API
- **Visualizações de página**: Seguimento automático da navegação na página
  utilizando o Phoenix LiveView
- **Eventos personalizados**: Eventos específicos da aplicação para utilização
  de funcionalidades e interações do utilizador

### Considerações sobre privacidade {#posthog-privacy}

- Para utilizadores autenticados, o PostHog utiliza o ID único do utilizador
  como identificador distinto e inclui o seu endereço de correio eletrónico
- Para utilizadores anónimos, o PostHog utiliza a persistência apenas na memória
  para evitar armazenar dados localmente
- Todas as análises respeitam a privacidade do utilizador e seguem as melhores
  práticas de proteção de dados
- Os dados do PostHog são processados de acordo com a política de privacidade do
  PostHog e a sua configuração

## Métricas de Elixir {#elixir-metrics}

Por padrão, incluímos métricas do tempo de execução do Elixir, BEAM, Elixir e
algumas das bibliotecas que usamos. A seguir estão algumas das métricas que você
pode esperar ver:

- [Aplicação](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Fénix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Recomendamos que consulte essas páginas para saber que métricas estão
disponíveis e como as utilizar.

## Métricas de execuções {#runs-metrics}

Um conjunto de métricas relacionadas com as execuções Tuist.

### `tuist_runs_total` (contador) {#tuist_runs_total-counter}

O número total de execuções Tuist.

#### Etiquetas {#tuist-runs-total-tags}

| Etiqueta   | Descrição                                                                      |
| ---------- | ------------------------------------------------------------------------------ |
| `nome`     | O nome do comando `tuist` que foi executado, tal como `build`, `test`, etc.    |
| `is_ci`    | Um booleano indicando se o executor era um CI ou uma máquina de desenvolvedor. |
| `estatuto` | `0` em caso de sucesso de `` , `1` em caso de insucesso de `` .                |

### `tuist_runs_duration_milliseconds` (histograma) {#tuist_runs_duration_milliseconds-histogram}

A duração total de cada execução da tuist em milissegundos.

#### Etiquetas {#tuist-runs-duration-miliseconds-tags}

| Etiqueta   | Descrição                                                                      |
| ---------- | ------------------------------------------------------------------------------ |
| `nome`     | O nome do comando `tuist` que foi executado, tal como `build`, `test`, etc.    |
| `is_ci`    | Um booleano indicando se o executor era um CI ou uma máquina de desenvolvedor. |
| `estatuto` | `0` em caso de sucesso de `` , `1` em caso de insucesso de `` .                |

## Métricas de cache {#cache-metrics}

Um conjunto de métricas relacionadas com a Cache Tuist.

### `tuist_cache_events_total` (contador) {#tuist_cache_events_total-counter}

O número total de eventos de cache binária.

#### Etiquetas {#tuist-cache-events-total-tags}

| Etiqueta         | Descrição                                                        |
| ---------------- | ---------------------------------------------------------------- |
| `tipo de evento` | Pode ser um dos seguintes: `local_hit`, `remote_hit`, ou `miss`. |

### `tuist_cache_uploads_total` (counter) {#tuist_cache_uploads_total-counter}

O número de carregamentos para a cache binária.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

O número de bytes carregados para a cache binária.

### `tuist_cache_downloads_total` (contador) {#tuist_cache_downloads_total-counter}

O número de descarregamentos para a cache binária.

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

O número de bytes descarregados da cache binária.

---

## Métricas de pré-visualizações {#previews-metrics}

Um conjunto de métricas relacionadas com a funcionalidade de pré-visualização.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

O número total de pré-visualizações carregadas.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

O número total de pré-visualizações descarregadas.

---

## Métricas de armazenamento {#métricas de armazenamento}

Um conjunto de métricas relacionadas com o armazenamento de artefactos num
armazenamento remoto (por exemplo, s3).

> [Estas métricas são úteis para compreender o desempenho das operações de
> armazenamento e para identificar potenciais estrangulamentos.

### `tuist_storage_get_object_size_size_bytes` (histograma) {#tuist_storage_get_object_size_size_bytes-histogram}

O tamanho (em bytes) de um objeto obtido a partir do armazenamento remoto.

#### Etiquetas {#tuist-storage-get-object-size-size-bytes-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |


### `tuist_storage_get_object_size_duration_miliseconds` (histograma) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

A duração (em milissegundos) da obtenção de um tamanho de objeto a partir do
armazenamento remoto.

#### Etiquetas {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

O número de vezes que um tamanho de objeto foi obtido a partir do armazenamento
remoto.

#### Etiquetas {#tuist-storage-get-object-size-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

A duração (em milissegundos) da eliminação de todos os objectos do armazenamento
remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiqueta        | Descrição                                                |
| --------------- | -------------------------------------------------------- |
| `projecto_slug` | O slug do projeto cujos objectos estão a ser eliminados. |


### `tuist_storage_delete_all_objects_count` (counter) {#tuist_storage_delete_all_objects_count-counter}

O número de vezes que todos os objectos de projeto foram eliminados do
armazenamento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-count-tags}

| Etiqueta        | Descrição                                                |
| --------------- | -------------------------------------------------------- |
| `projecto_slug` | O slug do projeto cujos objectos estão a ser eliminados. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

A duração (em milissegundos) do início de um carregamento para o armazenamento
remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_multipart_start_upload_duration_count` (counter) {#tuist_storage_multipart_start_upload_duration_count-counter}

O número de vezes que foi iniciado um carregamento para o armazenamento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histograma) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

A duração (em milissegundos) da pesquisa de um objeto como uma cadeia de
caracteres a partir do armazenamento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

O número de vezes que um objeto foi obtido como uma cadeia de caracteres a
partir do armazenamento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histograma) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

A duração (em milissegundos) da verificação da existência de um objeto no
armazenamento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

O número de vezes que a existência de um objeto foi verificada no armazenamento
remoto.

#### Etiquetas {#tuist-storage-check-object-existence-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

A duração (em milissegundos) da geração de um URL predefinido de transferência
para um objeto no armazenamento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

O número de vezes que um URL predefinido de download foi gerado para um objeto
no armazenamento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

A duração (em milissegundos) da geração de um URL predefinido de carregamento de
peças para um objeto no armazenamento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiqueta          | Descrição                                              |
| ----------------- | ------------------------------------------------------ |
| `chave_objecto`   | A chave de pesquisa do objeto no armazenamento remoto. |
| `número_de_peças` | O número de peça do objeto que está a ser carregado.   |
| `upload_id`       | O ID de carregamento do carregamento de várias partes. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

O número de vezes que um URL predefinido de carregamento de peças foi gerado
para um objeto no armazenamento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiqueta          | Descrição                                              |
| ----------------- | ------------------------------------------------------ |
| `chave_objecto`   | A chave de pesquisa do objeto no armazenamento remoto. |
| `número_de_peças` | O número de peça do objeto que está a ser carregado.   |
| `upload_id`       | O ID de carregamento do carregamento de várias partes. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

A duração (em milissegundos) da conclusão de um carregamento para o
armazenamento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |
| `upload_id`     | O ID de carregamento do carregamento de várias partes. |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

O número total de vezes que um carregamento foi concluído para o armazenamento
remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-count-tags}

| Etiqueta        | Descrição                                              |
| --------------- | ------------------------------------------------------ |
| `chave_objecto` | A chave de pesquisa do objeto no armazenamento remoto. |
| `upload_id`     | O ID de carregamento do carregamento de várias partes. |

---

## Métricas de autenticação {#authentication-metrics}

Um conjunto de métricas relacionadas com a autenticação.

### `tuist_authentication_token_refresh_error_total` (counter) {#tuist_authentication_token_refresh_error_total-counter}

O número total de erros de atualização de fichas.

#### Etiquetas {#tuist-authentication-token-refresh-error-total-tags}

| Etiqueta     | Descrição                                                                               |
| ------------ | --------------------------------------------------------------------------------------- |
| `versão_cli` | A versão do Tuist CLI que encontrou o erro.                                             |
| `razão`      | O motivo do erro de atualização do token, como `invalid_token_type` ou `invalid_token`. |

---

## Métricas de projectos {#projects-metrics}

Um conjunto de métricas relacionadas com os projectos.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

O número total de projectos.

---

## Métricas de contas {#accounts-metrics}

Um conjunto de métricas relacionadas com contas (utilizadores e organizações).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

O número total de organizações.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

O número total de utilizadores.


## Métricas da base de dados {#database-metrics}

Um conjunto de métricas relacionadas com a ligação à base de dados.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

O número de consultas à base de dados que estão numa fila de espera para serem
atribuídas a uma ligação à base de dados.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

O número de ligações à base de dados que estão prontas para serem atribuídas a
uma consulta da base de dados.


### `tuist_repo_pool_db_connection_connected` (counter) {#tuist_repo_pool_db_connection_connected-counter}

O número de ligações que foram estabelecidas à base de dados.

### `tuist_repo_pool_db_connection_disconnected` (counter) {#tuist_repo_pool_db_connection_disconnected-counter}

O número de ligações que foram desligadas da base de dados.

## Métricas HTTP {#http-metrics}

Um conjunto de métricas relacionadas com as interações do Tuist com outros
serviços via HTTP.

### `tuist_http_request_count` (counter) {#tuist_http_request_count-last_value}

O número de pedidos HTTP de saída.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

A soma da duração dos pedidos de saída (incluindo o tempo que passaram à espera
de serem atribuídos a uma ligação).

### `tuist_http_request_duration_nanosecond_bucket` (distribuição) {#tuist_http_request_duration_nanosecond_bucket-distribution}
A distribuição da duração dos pedidos de saída (incluindo o tempo que passaram à
espera de serem atribuídos a uma ligação).

### `tuist_http_queue_count` (counter) {#tuist_http_queue_count-counter}

O número de pedidos que foram recuperados do conjunto.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

O tempo que demora a recuperar uma ligação do grupo.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

O tempo que uma ligação esteve inativa à espera de ser recuperada.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribuição) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

O tempo que demora a recuperar uma ligação do grupo.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribuição) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

O tempo que uma ligação esteve inativa à espera de ser recuperada.

### `tuist_http_connection_count` (counter) {#tuist_http_connection_count-counter}

O número de ligações que foram estabelecidas.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

O tempo que demora a estabelecer uma ligação com um anfitrião.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribuição) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

A distribuição do tempo que demora a estabelecer uma ligação com um anfitrião.

### `tuist_http_send_count` (contador) {#tuist_http_send_count-counter}

O número de pedidos que foram enviados depois de atribuídos a uma ligação do
grupo.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

O tempo que os pedidos demoram a ser concluídos depois de atribuídos a uma
ligação do grupo.

### `tuist_http_send_duration_nanoseconds_bucket` (distribuição) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

A distribuição do tempo que os pedidos demoram a ser concluídos depois de
atribuídos a uma ligação do grupo.

### `tuist_http_receive_count` (counter) {#tuist_http_receive_count-counter}

O número de respostas que foram recebidas de pedidos enviados.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

O tempo gasto a receber respostas.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribuição) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

A distribuição do tempo gasto na receção de respostas.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

O número de ligações disponíveis na fila de espera.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

O número de ligações de fila que estão a ser utilizadas.
