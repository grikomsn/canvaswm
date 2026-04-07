#!/bin/bash
# Setup GitHub secrets for Developer ID signing
# Run this script after exporting your Developer ID certificate

echo "Setting up GitHub secrets for CanvasWM code signing..."
echo ""
echo "Required secrets:"
echo "  1. DEVELOPER_ID_CERTIFICATE_P12 - Base64-encoded .p12 certificate file"
echo "  2. DEVELOPER_ID_CERTIFICATE_PASSWORD - Password for the .p12 file"
echo "  3. DEVELOPER_ID_NAME - Your Developer ID name (e.g., 'Developer ID Application: Griko Nibras')"
echo ""

# Check if gh CLI is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: gh CLI not authenticated. Run 'gh auth login' first."
    exit 1
fi

REPO="grikomsn/canvaswm"

# Function to set secret
set_secret() {
    local name=$1
    local value=$2
    
    if [ -z "$value" ]; then
        echo "⚠️  Skipping $name (empty value)"
        return
    fi
    
    echo "$value" | gh secret set "$name" --repo "$REPO"
    if [ $? -eq 0 ]; then
        echo "✓ Set $name"
    else
        echo "✗ Failed to set $name"
    fi
}

# Check for certificate file
if [ -f "~/DeveloperID.p12" ] || [ -f "$HOME/DeveloperID.p12" ]; then
    P12_FILE="${HOME}/DeveloperID.p12"
elif [ -f "DeveloperID.p12" ]; then
    P12_FILE="DeveloperID.p12"
else
    echo "Certificate file not found. Please export your Developer ID certificate from Keychain Access:"
    echo ""
    echo "  1. Open Keychain Access"
    echo "  2. Find 'Developer ID Application: Your Name' certificate"
    echo "  3. Right-click → Export"
    echo "  4. Save as .p12 format (e.g., ~/DeveloperID.p12)"
    echo "  5. Remember the password you set"
    echo ""
    read -p "Enter path to your .p12 file: " P12_FILE
fi

if [ -f "$P12_FILE" ]; then
    echo "Found certificate: $P12_FILE"
    
    # Encode to base64
    P12_BASE64=$(base64 -i "$P12_FILE")
    
    # Set the secret
    echo "$P12_BASE64" | gh secret set DEVELOPER_ID_CERTIFICATE_P12 --repo "$REPO"
    if [ $? -eq 0 ]; then
        echo "✓ Set DEVELOPER_ID_CERTIFICATE_P12"
    else
        echo "✗ Failed to set DEVELOPER_ID_CERTIFICATE_P12"
    fi
else
    echo "⚠️  Certificate file not found at: $P12_FILE"
    echo "   You'll need to set DEVELOPER_ID_CERTIFICATE_P12 manually:"
    echo "   base64 -i YourCertificate.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12 --repo $REPO"
fi

# Set certificate password
read -s -p "Enter certificate password (or press Enter to skip): " CERT_PASSWORD
echo ""
if [ -n "$CERT_PASSWORD" ]; then
    set_secret "DEVELOPER_ID_CERTIFICATE_PASSWORD" "$CERT_PASSWORD"
fi

# Set Developer ID name
read -p "Enter Developer ID name (e.g., 'Developer ID Application: Griko Nibras'): " DEV_ID_NAME
if [ -n "$DEV_ID_NAME" ]; then
    set_secret "DEVELOPER_ID_NAME" "$DEV_ID_NAME"
fi

echo ""
echo "Setup complete!"
echo ""
echo "Verify secrets were set:"
gh secret list --repo "$REPO"
