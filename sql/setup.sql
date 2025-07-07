-------------------------------------
-- Create Tables
-------------------------------------
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

---------------------------------------------------------
-- Create Fake Data UDF using Python Faker Library 
---------------------------------------------------------
CREATE OR REPLACE FUNCTION FAKER(LOCALES VARCHAR(16777216), PROVIDER VARCHAR(16777216), PARAMETERS VARCHAR(16777216))
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('faker')
HANDLER = 'compute'
AS '
import json, datetime, decimal
from faker import Faker

locale_list = [''en_US'', ''en_GB'',''de_DE'', ''de_AT'', ''de_CH'',''pl_PL'', ''fr_FR'', ''es_ES'', ''it_IT'', ''nl_NL'', ''dk_DK'', ''ru_RU'', ''en_PH'']
faker = Faker(locale_list)

def compute(locales, provider, parameters):
    try:
        fake = faker[locales]
    except:
        raise Exception (''Country not implemented.'')
    if len(parameters) > 2:
        data = fake.format(provider,parameters)
    else:
        data = fake.format(provider)
    data = json.loads(json.dumps(data, default=default_json_transform).replace(''\\\\n'','', ''))
    return data

# format incompatible data types
def default_json_transform(obj):
    if isinstance(obj, decimal.Decimal):
        return str(obj)
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    raise TypeError
';


