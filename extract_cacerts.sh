#!/bin/bash

# Tool to generate a Java-style "cacerts" keystore from the installed
# system certificates

set -e

jdk=${1:-/app/jdk}

function get_alias() {
	local alias=""
	local issuer="${1// /},"
	# Determine which attribute to use for the alias
	if [[ $issuer =~ CN= ]] ; then
		# Use the "Common Name" if available
		alias=$(echo "$issuer" | sed -e 's/.*CN=\([^,]*\),.*/\1/')
		# Unless it's GlobalSign, because of non-uniqueness
		if [[ $alias == GlobalSign ]] ; then
			# In which case use the "Organisational Unit" instead
			alias=$(echo "$issuer" | sed -e 's/.*OU=\([^,]*\),.*/\1/')
		fi
	elif [[ $issuer =~ OU= ]] ; then
		# Use the "Organisational Unit" if CN is unavailable
		alias=$(echo "$issuer" | sed -e 's/.*OU=\([^,]*\),.*/\1/')
	else
		# Use the "Organisation" if CN and OU are unavailable
		alias=$(echo "$issuer" | sed -e 's/.*O=\([^,]*\),.*/\1/')
	fi
	# Return only acsii chars, all lowercase, all one word, just to be consistent with what p11-kit would do
	echo "$alias" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9()._-]//g'
}

declare -A used_aliases

for certificate in $(ls /etc/ssl/certs/*.pem) ; do
	cert=$($jdk/bin/keytool -printcert -file $certificate)
	issuer=$(echo "$cert" | grep '^Issuer' | cut -d' ' -f1 --complement)
	fprint=$(echo "$cert" | grep 'SHA1:' | cut -d' ' -f3)
	alias=$(get_alias "$issuer")

	# If this alias has already been used, add a unique digit to the end
	if [[ -v "used_aliases[$alias]" ]]; then
		original_alias="$alias"
		for i in {1..9}; do
			alias="${original_alias}$i"
			[[ -v "used_aliases[$alias]" ]] || break
		done

		echo "Note: renaming duplicate alias $original_alias -> $alias" >&2
	fi

	echo "Adding $fprint ($alias)"
	$jdk/bin/keytool -importcert -noprompt -alias $alias -storepass changeit -storetype JKS -keystore cacerts -file $certificate
	used_aliases["$alias"]=1
done

rm $jdk/lib/security/cacerts
mv cacerts $jdk/lib/security/cacerts