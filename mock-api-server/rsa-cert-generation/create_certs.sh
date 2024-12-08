#!/usr/bin/env bash

##################################################################################################
# ROOT CA
# Using home directory instead of /root
BASE_DIR="$HOME/ca/rsa"
mkdir -p "$BASE_DIR/certs" "$BASE_DIR/csr" "$BASE_DIR/newcerts" "$BASE_DIR/private" "$BASE_DIR/volumed_dir"
# Read and write to root in private folder
chmod 700 "$BASE_DIR/private"
touch "$BASE_DIR/index.txt"
# Echo the user id
echo 1000 > "$BASE_DIR/serial"
echo 1000 > "$BASE_DIR/crlnumber"

# Generating the root key for the Certificate Authority | No passphrase for simplicity within docker
openssl genrsa -out "$BASE_DIR/private/ca.key.pem" 4096
# Set permissions for the key file
chmod 600 "$BASE_DIR/private/ca.key.pem"

# Create the certificate for the authority in non-interactive mode
openssl req -config "$BASE_DIR/openssl.cnf" \
      -key "$BASE_DIR/private/ca.key.pem" \
      -new -x509 -days 3650 -sha256 -extensions v3_ca \
      -out "$BASE_DIR/certs/ca.cert.pem" \
      -subj "/C=UA/ST=Rivne/L=Rivne/O=SoftServerAcademy/OU=Engineering/CN=SoftServer Engineering Root CA"

# Set read permissions for the certificate
chmod 644 "$BASE_DIR/certs/ca.cert.pem"

##################################################################################################
# INTERMEDIATE CA
# Now create the intermediate CA
INTERMEDIATE_DIR="$BASE_DIR/intermediate"
mkdir -p "$INTERMEDIATE_DIR/certs" "$INTERMEDIATE_DIR/csr" "$INTERMEDIATE_DIR/newcerts" "$INTERMEDIATE_DIR/private"
chmod 700 "$INTERMEDIATE_DIR/private"

# Create a serial file to add serial numbers to our certificates
echo 2000 > "$INTERMEDIATE_DIR/serial"
echo 2000 > "$INTERMEDIATE_DIR/crlnumber"
touch "$INTERMEDIATE_DIR/index.txt"

openssl genrsa -out "$INTERMEDIATE_DIR/private/intermediate.key.pem" 4096
chmod 600 "$INTERMEDIATE_DIR/private/intermediate.key.pem"

# Create the intermediate certificate signing request using the intermediate CA config
openssl req -config "$INTERMEDIATE_DIR/openssl.cnf" \
      -key "$INTERMEDIATE_DIR/private/intermediate.key.pem" \
      -new -sha256 \
      -out "$INTERMEDIATE_DIR/csr/intermediate.csr.pem" \
      -subj "/C=UA/ST=Rivne/L=Rivne/O=SoftServerAcademy/OU=Engineering/CN=SoftServer Engineering Intermediate CA"

# Create an intermediate certificate, by signing the CSR with the CA key
echo -e "y\ny\n" | openssl ca -config "$BASE_DIR/openssl.cnf" \
      -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in "$INTERMEDIATE_DIR/csr/intermediate.csr.pem" \
      -out "$INTERMEDIATE_DIR/certs/intermediate.cert.pem"

# Set read permissions for the intermediate certificate
chmod 644 "$INTERMEDIATE_DIR/certs/intermediate.cert.pem"

##################################################################################################
# CN = MOCK HOSTNAME
##################################################################################################
# Replace <mock-hostname> in openssl.cnf file with MOCK_HOSTNAME environment variable
sed -i '' "s+<mock-hostname>+$MOCK_HOSTNAME+g" "$INTERMEDIATE_DIR/openssl.cnf"

# Generate the key for the mock server
openssl genrsa -out "$INTERMEDIATE_DIR/private/mock.key.pem" 4096
chmod 600 "$INTERMEDIATE_DIR/private/mock.key.pem"

# Create the certificate signing request for the mock server
openssl req -config "$INTERMEDIATE_DIR/openssl.cnf" \
      -key "$INTERMEDIATE_DIR/private/mock.key.pem" \
      -new -sha256 -out "$INTERMEDIATE_DIR/csr/mock.csr.pem" \
      -subj "/C=UA/ST=Rivne/L=Rivne/O=SoftServerAcademy/OU=Engineering/CN=$MOCK_HOSTNAME"

# Sign the mock server certificate with the intermediate CA
echo -e "y\ny\n" | openssl ca -config "$INTERMEDIATE_DIR/openssl.cnf" \
      -extensions leaf_cert -days 365 -notext -md sha256 \
      -in "$INTERMEDIATE_DIR/csr/mock.csr.pem" \
      -out "$INTERMEDIATE_DIR/certs/mock.cert.pem"

chmod 644 "$INTERMEDIATE_DIR/certs/mock.cert.pem"

##################################################################################################
# Creating chains and copy certs to the volumed_dir
##################################################################################################
# Create the certificate chain with intermediate and root certificates
cat "$INTERMEDIATE_DIR/certs/intermediate.cert.pem" \
    "$BASE_DIR/certs/ca.cert.pem" > "$BASE_DIR/certs/ca-chain.cert.pem"
chmod 644 "$BASE_DIR/certs/ca-chain.cert.pem"

# Create the full certificate chain
cat "$INTERMEDIATE_DIR/certs/mock.cert.pem" \
    "$INTERMEDIATE_DIR/certs/intermediate.cert.pem" \
    "$BASE_DIR/certs/ca.cert.pem" > "$BASE_DIR/certs/full-chain.cert.pem"
chmod 644 "$BASE_DIR/certs/full-chain.cert.pem"

# Copy certificates to the volumed directory
cp "$BASE_DIR/certs/ca-chain.cert.pem" "$BASE_DIR/volumed_dir/ca-chain.cert.pem"
cp "$BASE_DIR/certs/full-chain.cert.pem" "$BASE_DIR/volumed_dir/full-chain.cert.pem"
cp "$BASE_DIR/certs/ca.cert.pem" "$BASE_DIR/volumed_dir/ca.cert.pem"
cp "$INTERMEDIATE_DIR/certs/intermediate.cert.pem" "$BASE_DIR/volumed_dir/intermediate.cert.pem"
cp "$INTERMEDIATE_DIR/certs/mock.cert.pem" "$BASE_DIR/volumed_dir/mock.cert.pem"
cp "$INTERMEDIATE_DIR/private/mock.key.pem" "$BASE_DIR/volumed_dir/mock.key.pem"

echo "Certificates and keys have been successfully created and copied to ~/ca/rsa/volumed_dir"
