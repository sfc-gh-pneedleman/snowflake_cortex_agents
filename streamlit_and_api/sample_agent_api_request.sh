#
# SET SNOWFLAKE_ACCOUNT_BASE_URL=https://org-account.snowflakecomputing.com
# SET PAT=my_programmatic_access_token
#

#curl command
curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/cortex/agent:run" \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--header "Authorization: Bearer $PAT" \
--data '{
    "model": "claude-3-7-sonnet",
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": "What are the top 10 total line amounts grouped by state?"
                }
            ]
        }
    ],
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "data_model"
            }
        },
        {
            "tool_spec": {
                "type": "sql_exec",
                "name": "sql_exec"
            }
        },
        {
          "tool_spec": {
                "type": "cortex_search",
                "name": "comment_search"
            }
        }
    ],
    "tool_resources": {
        "data_model": {"semantic_view": "SNOW_DB.SNOW_SCHEMA.BILLING_ANALYST_SEMANTIC_MODEL"},
        "comment_search": {
                    "name": "SNOW_DB.SNOW_SCHEMA.customer_comment_search_service",
                    "id_column": "COMMENT_ID",
                    "max_results": 5
            }
    }
}'