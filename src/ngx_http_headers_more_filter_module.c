#define DDEBUG 0

#include "ddebug.h"

#include "ngx_http_headers_more_filter_module.h"

#include <ngx_config.h>
#include <ctype.h>

typedef struct ngx_http_header_val_s  ngx_http_header_val_t;

typedef ngx_int_t (*ngx_http_set_header_pt)(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

typedef struct {
    ngx_str_t                  name;
    ngx_uint_t                 offset;
    ngx_http_set_header_pt     handler;
} ngx_http_set_header_t;

struct ngx_http_header_val_s {
    ngx_str_t                  value;
    ngx_uint_t                 hash;
    ngx_str_t                  key;
    ngx_http_set_header_pt     handler;
    ngx_uint_t                 offset;
};

/* config handlers */

static void *ngx_http_headers_more_create_conf(ngx_conf_t *cf);

static char *ngx_http_headers_more_merge_conf(ngx_conf_t *cf,
    void *parent, void *child);

static char * ngx_http_headers_more_set_headers(ngx_conf_t *cf,
        ngx_command_t *cmd, void *conf);

static char * ngx_http_headers_more_clear_headers(ngx_conf_t *cf,
        ngx_command_t *cmd, void *conf);

static char * ngx_http_headers_more_config_helper(ngx_conf_t *cf, ngx_command_t *cmd,
        void *conf, ngx_http_set_header_t *header_handlers);

static ngx_int_t ngx_http_headers_more_parse_header(ngx_log_t *log,
        ngx_str_t *cmd_name, ngx_str_t *raw_header, ngx_array_t *headers,
        ngx_http_set_header_t *header_handlers);

static ngx_int_t ngx_http_headers_more_parse_types(ngx_log_t *log,
        ngx_str_t *cmd_name, ngx_str_t *value, ngx_array_t *types);

static ngx_int_t ngx_http_headers_more_parse_statuses(ngx_log_t *log,
        ngx_str_t *cmd_name, ngx_str_t *value, ngx_array_t *statuses);

/* header setters and clearers */

static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_header(ngx_http_request_t *r,
    ngx_http_header_val_t *hv, ngx_str_t *value);

/* directive executer */

static ngx_int_t ngx_http_headers_more_exec_cmd(ngx_http_request_t *r,
        ngx_http_headers_more_cmd_t *cmd);

/* filter handlers */

static ngx_int_t ngx_http_headers_more_filter_init(ngx_conf_t *cf);

/* utilities */

static ngx_flag_t ngx_http_headers_more_check_type(ngx_http_request_t *r, ngx_array_t *types);

static ngx_flag_t
ngx_http_headers_more_check_status(ngx_http_request_t *r, ngx_array_t *statuses);

static ngx_http_set_header_t  ngx_http_headers_more_set_handlers[] = {

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_out_t, content_length),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Type"),
                 offsetof(ngx_http_headers_out_t, content_type),
                 ngx_http_set_builtin_header },

    { ngx_null_string, 0, ngx_http_set_header }
};

static ngx_http_set_header_t  ngx_http_headers_more_clear_handlers[] = {

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_clear_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_out_t, content_length),
                 ngx_http_clear_builtin_header },

    { ngx_string("Content-Type"),
                 offsetof(ngx_http_headers_out_t, content_type),
                 ngx_http_clear_builtin_header },

    { ngx_null_string, 0, ngx_http_clear_header }
};

static ngx_command_t  ngx_http_headers_more_filter_commands[] = {

    { ngx_string("more_set_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_1MORE,
      ngx_http_headers_more_set_headers,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

    { ngx_string("more_clear_headers"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
                        |NGX_CONF_1MORE,
      ngx_http_headers_more_clear_headers,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL},

      ngx_null_command
};

static ngx_http_module_t  ngx_http_headers_more_filter_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_headers_more_filter_init,     /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_headers_more_create_conf,     /* create location configuration */
    ngx_http_headers_more_merge_conf       /* merge location configuration */
};

ngx_module_t  ngx_http_headers_more_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_headers_more_filter_module_ctx,   /* module context */
    ngx_http_headers_more_filter_commands,      /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};

static ngx_http_output_header_filter_pt  ngx_http_next_header_filter;

static ngx_int_t
ngx_http_headers_more_filter(ngx_http_request_t *r)
{
    ngx_int_t                       rc;
    /* ngx_str_t                       value; */
    ngx_uint_t                      i;
    ngx_http_headers_more_conf_t    *conf;
    ngx_http_headers_more_cmd_t     *cmd;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_headers_more_filter_module);

    if (conf->cmds) {
        cmd = conf->cmds->elts;
        for (i = 0; i < conf->cmds->nelts; i++) {
            rc = ngx_http_headers_more_exec_cmd(r, cmd);
            if (rc != NGX_OK) {
                return rc;
            }
        }
    }

    return ngx_http_next_header_filter(r);
}

static ngx_int_t
ngx_http_headers_more_exec_cmd(ngx_http_request_t *r,
        ngx_http_headers_more_cmd_t *cmd)
{
    ngx_http_header_val_t           *h;
    ngx_uint_t                      i;

    if (!cmd->headers) {
        return NGX_OK;
    }

    if (cmd->types) {
        if ( ! ngx_http_headers_more_check_type(r, cmd->types) ) {
            return NGX_OK;
        }
    }

    if (cmd->statuses) {
        if ( ! ngx_http_headers_more_check_status(r, cmd->statuses) ) {
            return NGX_OK;
        }
    }

    h = cmd->headers->elts;
    for (i = 0; i < cmd->headers->nelts; i++) {

        if (h[i].handler(r, &h[i], &h[i].value) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_headers_more_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_headers_more_filter;

    return NGX_OK;
}

static ngx_flag_t
ngx_http_headers_more_check_type(ngx_http_request_t *r, ngx_array_t *types)
{
    ngx_uint_t          i;
    ngx_str_t           *t;

    t = types->elts;
    for (i = 0; i < types->nelts; i++) {
        if (r->headers_out.content_type.len == t[i].len
                && ngx_strcmp(r->headers_out.content_type.data,
                    t[i].data) == 0)
        {
            return 1;
        }
    }

    return 0;
}

static ngx_flag_t
ngx_http_headers_more_check_status(ngx_http_request_t *r, ngx_array_t *statuses)
{
    ngx_uint_t          i;
    ngx_uint_t          *status;

    status = statuses->elts;
    for (i = 0; i < statuses->nelts; i++) {
        if (r->headers_out.status == status[i]) {
            return 1;
        }
    }

    return 0;
}

static void *
ngx_http_headers_more_create_conf(ngx_conf_t *cf)
{
    ngx_http_headers_more_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_headers_more_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->cmds = NULL;
     */

    return conf;
}


static char *
ngx_http_headers_more_merge_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_uint_t                   i;
    ngx_http_headers_more_cmd_t  *prev_cmd, *cmd;
    ngx_http_headers_more_conf_t *prev = parent;
    ngx_http_headers_more_conf_t *conf = child;

    if (conf->cmds == NULL) {
        conf->cmds = prev->cmds;
    } else if (prev->cmds && prev->cmds->nelts) {
        cmd = ngx_array_push_n(conf->cmds, prev->cmds->nelts);
        prev_cmd = prev->cmds->elts;
        for (i = 0; i < prev->cmds->nelts; i++) {
            cmd[i] = prev_cmd[i];
        }
    }

    return NGX_CONF_OK;
}

static char *
ngx_http_headers_more_set_headers(ngx_conf_t *cf,
        ngx_command_t *cmd, void *conf)
{
    return ngx_http_headers_more_config_helper(cf, cmd, conf,
            ngx_http_headers_more_set_handlers);
}

static char * ngx_http_headers_more_clear_headers(ngx_conf_t *cf,
        ngx_command_t *cmd, void *conf)
{
    return ngx_http_headers_more_config_helper(cf, cmd, conf,
            ngx_http_headers_more_clear_handlers);
}

static char *
ngx_http_headers_more_config_helper(ngx_conf_t *cf, ngx_command_t *ngx_cmd,
        void *conf, ngx_http_set_header_t *header_handlers)
{
    ngx_http_headers_more_conf_t      *hcf = conf;

    ngx_uint_t                         i;
    ngx_http_headers_more_cmd_t       *cmd;
    ngx_str_t                         *arg;
    ngx_flag_t                         ignore_next_arg;
    ngx_str_t                         *cmd_name;
    ngx_int_t                          rc;

    if (hcf->cmds == NULL) {
        hcf->cmds = ngx_array_create(cf->pool, 1,
                                        sizeof(ngx_http_headers_more_cmd_t));
    }

    cmd = ngx_array_push(hcf->cmds);

    if (cmd == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->headers = ngx_array_create(cf->pool, 1,
                            sizeof(ngx_http_header_val_t));
    if (cmd->headers == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->types = ngx_array_create(cf->pool, 1,
                            sizeof(ngx_str_t));
    if (cmd->types == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->statuses = ngx_array_create(cf->pool, 1,
                            sizeof(ngx_uint_t));
    if (cmd->statuses == NULL) {
        return NGX_CONF_ERROR;
    }

    arg = cf->args->elts;

    cmd_name = &arg[0];

    ignore_next_arg = 0;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ignore_next_arg || arg[i].len == 0) {
            continue;
        }

        if (arg[i].data[0] != '-') {
            rc = ngx_http_headers_more_parse_header(cf->log, cmd_name,
                    &arg[i], cmd->headers, header_handlers);

            if (rc != NGX_OK) {
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (arg[i].len == 2) {
            if (arg[i].data[1] == 't') {
                if (cmd->types) {
                    ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                          "%V: option -t may only appear once.",
                          cmd_name);

                    return NGX_CONF_ERROR;
                }

                if (i == cf->args->nelts - 1) {
                    ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                          "%V: option -t takes an argument.",
                          cmd_name);

                    return NGX_CONF_ERROR;
                }

                rc = ngx_http_headers_more_parse_types(cf->log, cmd_name, &arg[i + 1], cmd->types);

                if (rc != NGX_OK) {
                    return NGX_CONF_ERROR;
                }

                ignore_next_arg = 1;

                continue;
            } else if (arg[i].data[1] == 's') {
                if (cmd->statuses) {
                    ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                          "%V: option -s may only appear once.",
                          cmd_name
                          );

                    return NGX_CONF_ERROR;
                }

                if (i == cf->args->nelts - 1) {
                    ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                          "%V: option -s takes an argument.",
                          cmd_name
                          );

                    return NGX_CONF_ERROR;
                }

                rc = ngx_http_headers_more_parse_statuses(cf->log, cmd_name,
                        &arg[i + 1], cmd->statuses);

                if (rc != NGX_OK) {
                    return NGX_CONF_ERROR;
                }

                ignore_next_arg = 1;

                continue;
            }
        }

        ngx_log_error(NGX_LOG_ERR, cf->log, 0,
              "%V: invalid option name: \"%V\"",
              cmd_name, &arg[i]);

        return NGX_CONF_ERROR;
    }

    if (cmd->types->nelts == 0) {
        cmd->types = NULL;
    }

    if (cmd->statuses->nelts == 0) {
        cmd->statuses = NULL;
    }

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_http_headers_more_parse_header(ngx_log_t *log, ngx_str_t *cmd_name,
        ngx_str_t *raw_header, ngx_array_t *headers,
        ngx_http_set_header_t *header_handlers)
{
    ngx_http_header_val_t             *hv;
    ngx_http_set_header_t             *set;
    ngx_uint_t                        i;
    ngx_str_t                         key = ngx_string("");
    ngx_str_t                         value = ngx_string("");
    ngx_flag_t                        seen_end_of_key;

    hv = ngx_array_push(headers);
    if (hv == NULL) {
        return NGX_ERROR;
    }

    seen_end_of_key = 0;
    for (i = 0; i < raw_header->len; i++) {
        if (key.len == 0) {
            if (isspace(raw_header->data[i])) {
                continue;
            }

            key.data = raw_header->data;
            key.len  = 1;

            continue;
        }

        if (!seen_end_of_key) {
            if (raw_header->data[i] == ':'
                    || isspace(raw_header->data[i])) {
                seen_end_of_key = 1;
                continue;
            }

            key.len++;

            continue;
        }

        if (value.len == 0) {
            if (raw_header->data[i] == ':'
                    || isspace(raw_header->data[i])) {
                continue;
            }

            value.data = &raw_header->data[i];
            value.len  = 1;
        }

        value.len++;
    }

    if (key.len == 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
              "%V: no key found in the header argument: %V",
              cmd_name, raw_header);

        return NGX_ERROR;
    }

    hv->hash = 1;
    hv->key = key;
    hv->value = value;
    hv->offset = 0;

    set = header_handlers;
    for (i = 0; 1; i++) {
        if (set[i].name.len && (hv->key.len != set[i].name.len
                || ngx_strcasecmp(hv->key.data, set[i].name.data) != 0))
        {
            continue;
        }

        hv->offset = set[i].offset;
        hv->handler = set[i].handler;

        break;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_headers_more_parse_types(ngx_log_t *log, ngx_str_t *cmd_name,
    ngx_str_t *value, ngx_array_t *types)
{
    u_char          *p, *last;
    ngx_str_t       *t;

    p = value->data;
    last = p + value->len;

    for (; p != last; p++) {
        if (t == NULL) {
            if (isspace(*p)) {
                continue;
            }

            t = ngx_array_push(types);
            if (t == NULL) {
                return NGX_ERROR;
            }

            t->len = 1;
            t->data = p;

            continue;
        }

        if (isspace(*p)) {
            t = NULL;
            continue;
        }

        t->len++;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_headers_more_parse_statuses(ngx_log_t *log, ngx_str_t *cmd_name,
    ngx_str_t *value, ngx_array_t *statuses)
{
    u_char          *p, *last;
    ngx_uint_t      *s;

    p = value->data;
    last = p + value->len;

    for (; p != last; p++) {
        if (s == NULL) {
            if (isspace(*p)) {
                continue;
            }

            s = ngx_array_push(statuses);
            if (s == NULL) {
                return NGX_ERROR;
            }

            if (*p >= '0' && *p <= '9') {
                *s = *p - '0';
            } else {
                ngx_log_error(NGX_LOG_ERR, log, 0,
                      "%V: invalid digit \"%c\" found in "
                      "the status code list \"%V\"",
                      cmd_name, *p, value);

                return NGX_ERROR;
            }

            continue;
        }

        if (isspace(*p)) {
            s = NULL;
            continue;
        }

        if (*p >= '0' && *p <= '9') {
            *s *= 10;
            *s += *p - '0';
        } else {
            ngx_log_error(NGX_LOG_ERR, log, 0,
                  "%V: invalid digit \"%c\" found in "
                  "the status code list \"%V\"",
                  cmd_name, *p, value);

            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_set_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
        ngx_str_t *value)
{
    /* TODO */
    return NGX_OK;
}

static ngx_int_t
ngx_http_set_builtin_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
        ngx_str_t *value)
{
    /* TODO */
    return NGX_OK;
}

static ngx_int_t
ngx_http_clear_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
        ngx_str_t *value)
{
    /* TODO */
    return NGX_OK;
}

static ngx_int_t
ngx_http_clear_builtin_header(ngx_http_request_t *r, ngx_http_header_val_t *hv,
        ngx_str_t *value)
{
    /* TODO */
    return NGX_OK;
}

