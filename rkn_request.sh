#!/bin/bash

# этот файл должен быть в UTF-8

RS=1;

PEMFILE="";
EMAIL="";
ON="";
INN="";
OGRN="";

TMPDIR="/tmp";
DT=`date +"%Y+%m-%dT%H:%M:%S.000%:z"`;
REQFILE="${TMPDIR}"/"request.xml";
REQ_SIG_FILE="${REQFILE}"".sig";
CRT_CRT_FILE="${TMPDIR}"/"tmp_rkn.crt.crt";
CRT_KEY_FILE="${TMPDIR}"/"tmp_rkn.crt.key";

REQ_CURL_FILE="${TMPDIR}"/"req_curl_file.request";

REQ_CURL_GET_FILE="${TMPDIR}"/"req_curl_file.get";

#REQ_URL="http://vigruzki.rkn.gov.ru/services/OperatorRequestTest/?wsdl";
REQ_URL="http://vigruzki.rkn.gov.ru/services/OperatorRequest/?wsdl";
REQ_URL_TN="http://vigruzki.rkn.gov.ru/OperatorRequest/";

LGOST="/tmp/engine/bin/libgost_engine.so";

while getopts ":p:e:n:" opt; do
	case $opt in
		p) PEMFILE="${OPTARG}";;
		e) EMAIL="${OPTARG}";;
		n) ON="${OPTARG}";;
		:) echo "Option -$OPTARG requires an argument." >&2;;
		\?) echo "Invalid option: -$OPTARG" >&2;;
	esac;
done;

reqa="<?xml version='1.0' encoding='UTF-8'?>";
reqa+="<SOAP-ENV:Envelope xmlns:SOAP-ENV='http://schemas.xmlsoap.org/soap/envelope/' xmlns:ns1='"${REQ_URL_TN}"'>";
reqa+="<SOAP-ENV:Body>";

Create_xml_request()
{
	echo "1. Generating a request file";

	xml="<?xml version=\"1.0\" encoding=\"windows-1251\"?>\n";
	xml+="<request>\n";
	xml+="	<requestTime>%s</requestTime>\n";
	xml+="	<operatorName>%s</operatorName>\n";
	xml+="	<inn>%s</inn>\n";
	xml+="	<ogrn>%s</ogrn>\n";
	xml+="	<email>%s</email>\n";
	xml+="</request>\n";

	printf "${xml}" "${DT}" "${ON}" "${INN}" "${OGRN}" "${EMAIL}" | \
		iconv -f UTF-8 -t WINDOWS-1251 - > "${REQFILE}";
}

Create_sig_request()
{
	echo "2. Generating a signature file";

	sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' "${PEMFILE}" > "${CRT_KEY_FILE}";

	scmda="engine dynamic -pre SO_PATH:"${LGOST}" ";
	scmda+="-pre ID:gost -pre LIST_ADD:1 -pre LOAD -post gost ";
	scmda+="-pre CRYPT_PARAMS:id-Gost28147-89-CryptoPro-A-ParamSet";
	scmdb="smime -engine gost -sign -binary -signer "${CRT_CRT_FILE}" -inkey "${CRT_KEY_FILE}" ";
	scmdb+="-outform PEM -in "${REQFILE}" -out "${REQ_SIG_FILE}"";
	scmdc="exit";

	echo -e "${scmda}""\n""${scmdb}""\n""${scmdc}""\n"  | openssl > /dev/null 2>&1;
}

Create_getLastDumpDateEx_request()
{
	echo "3. Generating getLastDumpDateEx request";

	reqb+="<ns1:getLastDumpDateEx/>";
	reqb+="</SOAP-ENV:Body>";
	reqb+="</SOAP-ENV:Envelope>";

	echo "${reqa}""${reqb}" > "${REQ_CURL_FILE}";
}

Create_sendRequest_request()
{
	echo "5. Generating sendRequest request";

	reqc+="<ns1:sendRequest>";
	reqc+="<requestFile>'"`base64 -w 0 "${REQFILE}"`"'</requestFile>";
	reqc+="<signatureFile>'"`base64 -w 0 "${REQ_SIG_FILE}"`"'</signatureFile>";
	reqc+="<dumpFormatVersion>2.0</dumpFormatVersion>";
	reqc+="</ns1:sendRequest>";
	reqc+="</SOAP-ENV:Body>";
	reqc+="</SOAP-ENV:Envelope>";

	echo "${reqa}""${reqc}" > "${REQ_CURL_FILE}";
}

Create_getResult_request()
{
	echo "7. Generating getResult request";

	reqd+="<ns1:getResult><code>""${1}""</code></ns1:getResult>";
	reqd+="</SOAP-ENV:Body>";
	reqd+="</SOAP-ENV:Envelope>";

	echo "${reqa}""${reqd}" > "${REQ_CURL_FILE}";
}

if
	[ ! -f "${PEMFILE}" ] ||
	[[ ! "${EMAIL}" =~ (.+@.+\..+) ]] ||
	[[ ! "${ON}" =~ (.+) ]];
then
	echo "The arguments were not passed (1)";
else
	openssl x509 -inform PEM -outform PEM -in "${PEMFILE}" -out "${CRT_CRT_FILE}";

	R1="Subject: OGRN = ([0-9]{13}),.* INN = ([0-9]{10,12})";

	L=`openssl x509 -in "${CRT_CRT_FILE}" -text -noout \
		-certopt no_header,no_version,no_serial,no_signame,no_validity,no_issuer,no_pubkey,no_sigdump,no_aux`;

	if [[ ! ${L} =~ ${R1} ]];
	then
		echo "The arguments were not passed (2)";
	else
		OGRN=${BASH_REMATCH[1]};
		INN=${BASH_REMATCH[2]};

		echo EMAIL=""${EMAIL}"";
		echo ON=""${ON}"";
		echo INN=""${INN}"";
		echo OGRN="${OGRN}";

		Create_xml_request;

		Create_sig_request;

		Create_getLastDumpDateEx_request;

		LDMPDT=`curl --silent -H "Content-Type: application/soap+xml; charset=utf-8" --url ""${REQ_URL}"" \
			--data-binary @"${REQ_CURL_FILE}" 2>&1 | grep -oPm1 "(?<=<lastDumpDate>)[^<]+"`;

		if [ ${?} -eq 0 ]; then
			echo "4. Response to the request: ""${LDMPDT}";
			Create_sendRequest_request;

			REQ_CODE=`curl --silent -H "Content-Type: application/soap+xml; charset=utf-8" \
				--url ""${REQ_URL}"" --data-binary @"${REQ_CURL_FILE}" 2>&1 | grep -oPm1 "(?<=<code>)[^<]+"`;

			if [ ${?} -eq 0 ]; then
				echo "6. Response to the request: ""${REQ_CODE}";
				Create_getResult_request "${REQ_CODE}";

				echo "8. sleep";

				sleep 2m;

				curl --silent -H "Content-Type: application/soap+xml; charset=utf-8" \
					--url ""${REQ_URL}"" --data-binary @"${REQ_CURL_FILE}" 2>&1 > "${REQ_CURL_GET_FILE}";

				if [ ${?} -eq 0 ]; then
					echo "9. Generating zip-file";
					grep -oPm1 "(?<=<registerZipArchive>)[^<]+" "${REQ_CURL_GET_FILE}" | \
						base64 -d > dump.zip;

					RS=0;
				fi;
			fi;
		fi;
	fi;
fi;

exit ${RS};
