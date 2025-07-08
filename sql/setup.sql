-------------------------------------
-- Create Tables
-------------------------------------
--change to whatever DB and Schema you would like to run in 
USE SNOW_DB.SNOW_SCHEMA;

--CUSTOMER
create or replace TABLE CUSTOMER (
	COUNTRY VARCHAR(16777216),
	JOB_TITLE VARCHAR(16777216),
	CUSTOMER_ID VARCHAR(16777216),
	COMPANY VARCHAR(16777216),
	DOB DATE,
	CELL_PHONE VARCHAR(16777216),
	CITY VARCHAR(16777216),
	WORK_PHONE VARCHAR(16777216),
	STREET VARCHAR(16777216),
	HOME_PHONE VARCHAR(16777216),
	NAME VARCHAR(16777216),
	STATE VARCHAR(16777216),
	POSTCODE VARCHAR(16777216)
);

--INVOICES
create or replace TABLE INVOICES (
	INVOICE_ID NUMBER(19,0),
	CUSTOMER_ID VARCHAR(16777216),
	INVOICE_NUMBER VARCHAR(16777216),
	INVOICE_STATUS VARCHAR(16777216),
	INVOICE_DATE TIMESTAMP_NTZ(9),
	INVOICE_PAID_DATE DATE,
	PAYMENT_TO_INVOICE_IN_DAYS NUMBER(9,0),
	SRC_FILE_NAME VARCHAR(16777216)
);

--INVOICE_LINES
create or replace TABLE INVOICE_LINES (
	INVOICE_LINE_ID NUMBER(19,0),
	INVOICE_ID NUMBER(19,0),
	ITEM_CD VARCHAR(16777216),
	ITEM_PRICE NUMBER(38,2)
);

--Customer Comments 
create or replace TABLE CUSTOMER_COMMENTS (
	CUSTOMER_ID VARCHAR(16777216),
	COMMENT_TEXT VARCHAR(16777216),
	COMMENT_DATE TIMESTAMP_TZ
);

------------------------------------------------------
-- Create parquet file format for data loading
------------------------------------------------------

CREATE OR REPLACE FILE FORMAT PARQUET_FILE_FORMAT
	TYPE = PARQUET
	NULL_IF = ()
	USE_VECTORIZED_SCANNER = TRUE
;


------------------------------------------------------
--Load Data
------------------------------------------------------
--Moves files to internal or external stage and run these commands 

--customer
COPY INTO CUSTOMER
  FROM @parquet_data_stage/customer
FILE_FORMAT = PARQUET_FILE_FORMAT
MATCH_BY_COLUMN_NAME = 'CASE_INSENSITIVE';

--invoices
COPY INTO INVOICES
  FROM @parquet_data_stage/invoices
FILE_FORMAT = PARQUET_FILE_FORMAT
MATCH_BY_COLUMN_NAME = 'CASE_INSENSITIVE';

--invoice_lines 
COPY INTO INVOICE_LINES
  FROM @parquet_data_stage/invoice_lines
FILE_FORMAT = PARQUET_FILE_FORMAT
MATCH_BY_COLUMN_NAME = 'CASE_INSENSITIVE';

--alter session to load timestamps from parquet format into snowflake 
ALTER SESSION SET TIMESTAMP_INPUT_FORMAT = 'YYYY-MM-DD HH12:MI:SS.FF3 PM TZHTZM';

COPY INTO CUSTOMER_COMMENTS
  FROM   @parquet_data_stage/customer_comments
FILE_FORMAT = PARQUET_FILE_FORMAT
MATCH_BY_COLUMN_NAME = 'CASE_INSENSITIVE';


---------------------------------------------------------------
-- Create Cortex Search Services for various columns and data
---------------------------------------------------------------

--customer name
CREATE OR REPLACE CORTEX SEARCH SERVICE customer_name_search_service
  ON name
  WAREHOUSE = compute_xs_wh
  TARGET_LAG = '24 hour'
  AS (
      SELECT DISTINCT name FROM customer
  );


--customer comments; this command will take some time
CREATE OR REPLACE CORTEX SEARCH SERVICE customer_comment_search_service
  ON comment_text 
  ATTRIBUTES  customer_name
  WAREHOUSE = compute_m_wh
  TARGET_LAG = '24 hour'
  AS (
    SELECT
        c.name as CUSTOMER_NAME, 
		customer_id,
        CUSTOMER_NAME||' comment: ' || comment_text as comment_text
    FROM customer_comments cc JOIN CUSTOMER c ON cc.customer_id = c.customer_id
);


---------------------------------------------------------
-- Create Semantic View based on above tables 
---------------------------------------------------------
-- you can create via SQL or thought the UI in AI & ML -> Cortex Analyst -> Semantic Views
-- Sample yaml file also in this directly if prefer to use that over a view (BILLING_ANALYST_SEMANTIC_MODEL.yaml)  

create or replace semantic view BILLING_ANALYST_SEMANTIC_MODEL
	tables (
		CUSTOMER primary key (CUSTOMER_ID) with synonyms=('client','patron','buyer','purchaser','shopper','consumer','customer base') comment='This table stores information about individual customers, including their personal details such as name, date of birth, and contact information (home, work, and cell phone numbers), as well as their professional details (job title and company), and their address (street, city, state, postcode, and country).',
		INVOICES primary key (INVOICE_ID) with synonyms=('bills','receipts','invoices','statements','financial documents','payment records','sales records','transaction records','financial statements') comment='This table stores information about invoices, including the unique identifier, customer details, invoice number, status, date issued, date paid, and the number of days taken to pay the invoice, as well as the source file name from which the data was loaded.',
		INVOICE_LINES with synonyms=('INVOICE_DETAILS','BILLING_ITEMS','INVOICE_ENTRIES','CHARGES','LINE_ITEMS') comment='This table stores detailed information about individual items on an invoice, including a unique identifier for the invoice line, the associated invoice identifier, the item code, and the price of the item.'
	)
	relationships (
		CUSTOMER_TO_INVOICE as INVOICES(CUSTOMER_ID) references CUSTOMER(CUSTOMER_ID),
		INVOICE_TO_LINES as INVOICE_LINES(INVOICE_ID) references INVOICES(INVOICE_ID)
	)
	facts (
		INVOICES.PAYMENT_TO_INVOICE_IN_DAYS as PAYMENT_TO_INVOICE_IN_DAYS with synonyms=('days_to_pay_invoice','invoice_payment_turnaround','payment_processing_time','invoice_settlement_period','days_to_settle_invoice','payment_duration_after_invoice') comment='The number of days between the payment date and the invoice date.',
		INVOICE_LINES.ITEM_PRICE as ITEM_PRICE with synonyms=('item_cost','unit_price','price_per_item','item_value','cost_per_unit','unit_cost') comment='The price of each item on an invoice.'
	)
	dimensions (
		CUSTOMER.CITY as CITY with synonyms=('town','municipality','metropolis','urban_area','locality','settlement','borough','district','suburb','metropolitan_area') comment='The city where the customer is located.',
		CUSTOMER.COMPANY as COMPANY with synonyms=('organization','firm','business','employer','corporation','enterprise','institution','agency') comment='The COMPANY column represents the name of the company or organization that the customer is associated with, which can be a full company name or a combination of last names and a company suffix.',
		CUSTOMER.COUNTRY as COUNTRY with synonyms=('nation','land','territory','state','region','nationality','homeland','territory_name') comment='The country where the customer is located.',
		CUSTOMER.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_id','user_id','client_number','account_number','customer_account','unique_customer_identifier') comment='Unique identifier for each customer in the database, used to distinguish and track individual customer records.',
		CUSTOMER.HOME_PHONE as HOME_PHONE with synonyms=('residence_phone','landline','home_telephone','personal_phone','residential_phone','main_phone') comment='The customer''s home phone number, which may be in various formats, including international and domestic numbers with extensions.',
		CUSTOMER.JOB_TITLE as JOB_TITLE with synonyms=('occupation','profession','role','position','title','employment_title','job_position','career','vocation','professional_title') comment='The JOB_TITLE column contains the occupation or professional title of each customer, providing insight into their career and industry.',
		CUSTOMER.NAME as NAME with synonyms=('full_name','first_name','last_name','person_name','customer_name','individual_name','personal_name') comment='The name of the customer.',
		CUSTOMER.POSTCODE as POSTCODE with synonyms=('zip_code','postal_code','zip','postal','postcode_number','zip_code_number') comment='The POSTCODE column represents the postal code of the customer''s address, which is a unique code assigned to a geographic area by the postal service to facilitate mail sorting and delivery.',
		CUSTOMER.DOB as DOB with synonyms=('date_of_birth','birth_date','birthdate','birthday','date_of_birth_recorded') comment='Date of Birth of the customer.',
		CUSTOMER.STATE as STATE with synonyms=('province','region','territory','county','area','location','jurisdiction','district','division') comment='The state where the customer resides.',
		CUSTOMER.STREET as STREET with synonyms=('address','road','avenue','route','way','lane','boulevard','drive','thoroughfare') comment='The physical address of the customer''s residence.',
		INVOICES.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_id','client_number','account_holder_id','user_id') comment='Unique identifier for the customer who the invoice is associated with.',
		INVOICES.INVOICE_DATE as INVOICE_DATE with synonyms=('invoice_creation_date','invoice_issue_date','invoice_generated_date','billing_date','invoice_timestamp','document_date') comment='Date and time when the invoice was created.',
		INVOICES.INVOICE_ID as INVOICE_ID with synonyms=('invoice_number_key','invoice_identifier','invoice_code','invoice_reference','invoice_unique_id','invoice_serial_number') comment='Unique identifier for each invoice in the system.',
		INVOICES.INVOICE_NUMBER as INVOICE_NUMBER with synonyms=('bill_number','invoice_id','invoice_code','purchase_order_number','order_number','document_number','receipt_number') comment='Unique identifier for each invoice, typically used for tracking and referencing purposes.',
		INVOICES.INVOICE_PAID_DATE as INVOICE_PAID_DATE with synonyms=('payment_date','paid_on','invoice_settlement_date','date_paid','payment_completion_date','invoice_cleared_date') comment='Date on which the invoice was fully paid.',
		INVOICES.INVOICE_STATUS as INVOICE_STATUS with synonyms=('invoice_state','payment_status','invoice_condition','billing_status','payment_condition','invoice_position') comment='The current status of the invoice, indicating whether it has been paid, is overdue, or has not yet reached its due date.',
		INVOICES.SRC_FILE_NAME as SRC_FILE_NAME with synonyms=('source_file_name','file_origin','data_source','file_name','original_file_name','source_file_origin') comment='The name of the source file from which the invoice data was extracted, typically in PDF format.',
		INVOICE_LINES.INVOICE_ID as INVOICE_ID with synonyms=('bill_id','invoice_number','invoice_no','billing_id','order_id','purchase_id','sales_id') comment='Unique identifier for the invoice that this line item belongs to.',
		INVOICE_LINES.INVOICE_LINE_ID as INVOICE_LINE_ID with synonyms=('line_item_id','invoice_line_number','line_id','invoice_detail_id','transaction_line_id') comment='Unique identifier for each line item on an invoice.',
		INVOICE_LINES.ITEM_CD as ITEM_CD with synonyms=('item_code','product_code','item_number','product_id','sku','item_identifier') comment='Unique identifier for the item being invoiced.'
	)
	with extension (CA='{"tables":[{"name":"CUSTOMER","dimensions":[{"name":"CITY","sample_values":["Lindaberg","Andrewview","West Scottstad"]},{"name":"COMPANY","sample_values":["Duncan, Henry and Espinoza","Miller, Harris and Ferrell","Peters Group"]},{"name":"COUNTRY","sample_values":["US"]},{"name":"CUSTOMER_ID","sample_values":["7665919477","5755419949","1217634388"]},{"name":"HOME_PHONE","sample_values":["923.880.6244","(586)281-4033x5036","+1-281-529-0533x683"]},{"name":"JOB_TITLE","sample_values":["Speech and language therapist","Brewing technologist","Diplomatic Services operational officer"]},{"name":"NAME","sample_values":["Michael Morton","Sean Christensen","Danny Reed"],"cortex_search_service":{"database":"SNOW_DB","schema":"SNOW_SCHEMA","service":"CUSTOMER_NAME_SEARCH_SERVICE"}},{"name":"POSTCODE","sample_values":["20650","43346","37682"]},{"name":"STATE","sample_values":["Indiana","Virginia","Ohio"]},{"name":"STREET","sample_values":["37697 Kristy Grove","78455 Cherry Terrace","60617 Knight Island Apt. 924"]}],"time_dimensions":[{"name":"DOB","sample_values":["1928-04-10","2015-05-06","1920-04-12"]}]},{"name":"INVOICES","dimensions":[{"name":"CUSTOMER_ID","sample_values":["6495828142","1512804641","7750588458"]},{"name":"INVOICE_ID","sample_values":["154","155","166"]},{"name":"INVOICE_NUMBER","sample_values":["INV-0N0LG-95","INV-0N6JH-06","INV-0S5FX-31"]},{"name":"INVOICE_STATUS","sample_values":["Paid","Overdue","Not Due"]},{"name":"SRC_FILE_NAME","sample_values":["INVOICE_NO_INV-0N0LG-9520.pdf","INVOICE_NO_INV-0N6JH-0620.pdf","INVOICE_NO_INV-0S5FX-3120.pdf"]}],"facts":[{"name":"PAYMENT_TO_INVOICE_IN_DAYS","sample_values":["-5","-1","-27"]}],"time_dimensions":[{"name":"INVOICE_DATE","sample_values":["2022-03-28T09:56:16.000+0000","2022-03-19T22:37:24.000+0000","2022-05-02T22:40:07.000+0000"]},{"name":"INVOICE_PAID_DATE","sample_values":["2022-04-02","2022-03-20","2022-05-29"]}]},{"name":"INVOICE_LINES","dimensions":[{"name":"INVOICE_ID","sample_values":["102","471","315"]},{"name":"INVOICE_LINE_ID","sample_values":["2606","3199","877"]},{"name":"ITEM_CD","sample_values":["ITEM_1","ITEM_3","ITEM_2"]}],"facts":[{"name":"ITEM_PRICE","sample_values":["12.61","9750.22","8353.72"]}]}],"relationships":[{"name":"CUSTOMER_TO_INVOICE","relationship_type":"many_to_one","join_type":"inner"},{"name":"INVOICE_TO_LINES","relationship_type":"many_to_one","join_type":"inner"}],"custom_instructions":""}');

