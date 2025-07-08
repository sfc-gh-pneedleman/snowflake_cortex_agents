import streamlit as st
import json
import _snowflake
from snowflake.snowpark.context import get_active_session

session = get_active_session()

API_ENDPOINT = "/api/v2/cortex/agent:run"
API_TIMEOUT = 50000  # in milliseconds

CORTEX_SEARCH_SERVICES = "SNOW_DB.SNOW_SCHEMA.customer_comment_search_service"
SEMANTIC_MODELS = "SNOW_DB.SNOW_SCHEMA.BILLING_ANALYST_SEMANTIC_MODEL"


def run_snowflake_query(query):
    try:
        df = session.sql(query.replace(';',''))
        
        return df

    except Exception as e:
        st.error(f"Error executing SQL: {str(e)}")
        return None, None

def snowflake_api_call(query: str, limit: int = 10):
    
    payload = {
        "model": "claude-3-5-sonnet",
        "response_instruction": "You will always maintain a friendly tone and provide concise response.",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": query
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
            },
        ],
        "tool_resources": {
            "data_model": {"semantic_view": SEMANTIC_MODELS},
            "comment_search": {
                "name": CORTEX_SEARCH_SERVICES,
                 "title_column": "CUSTOMER_NAME",
                 "id_column": "CUSTOMER_ID",
                 "max_results": 5
            }
        }
    }
    
    try:
        resp = _snowflake.send_snow_api_request(
            "POST",  # method
            API_ENDPOINT,  # path
            {},  # headers
            {},  # params
            payload,  # body
            None,  # request_guid
            API_TIMEOUT,  # timeout in milliseconds,
        )
        
        if resp["status"] != 200:
            st.error(f"❌ HTTP Error: {resp['status']} - {resp.get('reason', 'Unknown reason')}")
            st.error(f"Response details: {resp}")
            return None
        
        try:
            response_content = json.loads(resp["content"])
        except json.JSONDecodeError:
            st.error("❌ Failed to parse API response. The server may have returned an invalid JSON format.")
            st.error(f"Raw response: {resp['content'][:200]}...")
            return None
            
        return response_content
            
    except Exception as e:
        st.error(f"Error making request: {str(e)}")
        return None

def process_sse_response(response):
    """Process SSE response"""
    text = ""
    sql = ""
    citations = []
    
    if not response:
        return text, sql, citations
    if isinstance(response, str):
        return text, sql, citations
    try:
        for event in response:
            if event.get('event') == "message.delta":
                data = event.get('data', {})
                delta = data.get('delta', {})
                
                for content_item in delta.get('content', []):
                    content_type = content_item.get('type')
                    if content_type == "tool_results":
                        tool_results = content_item.get('tool_results', {})
                        if 'content' in tool_results:
                            for result in tool_results['content']:
                                if result.get('type') == 'json':
                                    text += result.get('json', {}).get('text', '')
                                    search_results = result.get('json', {}).get('searchResults', [])
                                    for search_result in search_results:
                                        citations.append({'source_id':search_result.get('source_id',''), 'doc_id':search_result.get('doc_id', '')})
                                    sql = result.get('json', {}).get('sql', '')
                    if content_type == 'text':
                        text += content_item.get('text', '')
                            
    except json.JSONDecodeError as e:
        st.error(f"Error processing events: {str(e)}")
                
    except Exception as e:
        st.error(f"Error processing events: {str(e)}")
        
    return text, sql, citations

def main():
    st.title("Billing Analyst Agent Assistant")

    # Sidebar for new chat
    with st.sidebar:
        if st.button("New Conversation", key="new_chat"):
            st.session_state.messages = []
            st.rerun()

    # Initialize session state
    if 'messages' not in st.session_state:
        st.session_state.messages = []

    for message in st.session_state.messages:
        with st.chat_message(message['role']):
            st.markdown(message['content'].replace("•", "\n\n"))

    if query := st.chat_input("Would you like to search for?"):
        # Add user message to chat
        with st.chat_message("user"):
            st.markdown(query)
        st.session_state.messages.append({"role": "user", "content": query})
        
        # Get response from API
        with st.spinner("Processing your request..."):
            response = snowflake_api_call(query, 1)
            text, sql, citations = process_sse_response(response)

            #uncomment to view API response for debugging 
            #st.write(response)
            
            # Add assistant response to chat
            if text:
                text = text.replace("【†", "[")
                text = text.replace("†】", "]")
                st.session_state.messages.append({"role": "assistant", "content": text})
                
                with st.chat_message("assistant"):
                    st.markdown(text.replace("•", "\n\n"))
                    if citations:
                            st.write("Citations:")
                            for citation in citations:
                                doc_id = citation.get("doc_id", "")
                                if doc_id:
                                    query = f"SELECT name || ': ' || comment_text FROM customer_comments  cc JOIN customer c on CC.CUSTOMER_iD = C.Customer_ID WHERE c.customer_id = '{doc_id}'"
                                    result = run_snowflake_query(query)
                                    result_df = result.to_pandas()
                                    if not result_df.empty:
                                        transcript_text = result_df.iloc[0, 0]
                                    else:
                                        transcript_text = "No transcript available"
                        
                                    with st.expander(f"[{citation.get('source_id', '')}]"):
                                        st.write(transcript_text)

                   
            # Display SQL if present
            if sql:
                st.markdown("### Generated SQL")
                st.code(sql, language="sql")
                sales_results = run_snowflake_query(sql)
                if sales_results:
                    st.write("### Billing Analyst Metrics Report")
                    st.dataframe(sales_results)

if __name__ == "__main__":
    main()