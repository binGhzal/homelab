#!/bin/bash
# Proxmox Template Creator - Template Module

set -e

# Directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Source the centralized logging library
# Ensure logging.sh is available or provide basic fallbacks
if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
    source "$SCRIPT_DIR/lib/logging.sh"
    # Assuming init_logging is defined in logging.sh and handles its own LOG_FILE
    # For now, let's assume logging.sh's init_logging is sufficient or template.sh uses its own.
    # init_logging "template" # This might need adjustment based on logging.sh's final design
else
    echo "Warning: logging.sh not found. Using basic logging functions." >&2
    log_info() { echo "[INFO] [template.sh] $*"; }
    log_warn() { echo "[WARN] [template.sh] $*"; }
    log_error() { echo "[ERROR] [template.sh] $*"; }
    log_debug() { echo "[DEBUG] [template.sh] $*"; }
    # Define a basic handle_error if logging.sh is not available
    handle_error() {
        local exit_code=$1
        local line_num=$2
        echo "[ERROR] [template.sh] Error in script on line $line_num with exit code $exit_code." >&2
        # No LOG_FILE known here, so just stderr
        exit "$exit_code"
    }
fi

# Initialize logging system - this call needs to be correct based on logging.sh
# If init_logging is from the sourced library, it should be called after sourcing.
# If it sets a specific log file like /var/log/template_bootstrap.log, ensure that file is declared.
# For now, commenting out until logging.sh is finalized. The subtask is about bootstrap.sh logging.
# init_logging "template"

# Set up error trap. handle_error should be defined either from logging.sh or the fallback.
trap 'handle_error $? $LINENO' ERR

# --- Distribution Configuration ---
# Format: "distro_id|Display Name|cloud-init-support|url_template"
DISTRO_LIST=(
    "ubuntu|Ubuntu Server|yes|https://cloud-images.ubuntu.com/releases/%version%/release/ubuntu-%version%-server-cloudimg-amd64.img"
    "debian|Debian|yes|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    "centos|CentOS|yes|https://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-%version%.x86_64.qcow2"
    "rocky|Rocky Linux|yes|https://dl.rockylinux.org/pub/rocky/%version%/images/Rocky-%version%-GenericCloud.x86_64.qcow2"
    "alpine|Alpine Linux|no|https://dl-cdn.alpinelinux.org/alpine/v%version%/releases/x86_64/alpine-virt-%version%.0-x86_64.iso"
    "fedora|Fedora|yes|https://download.fedoraproject.org/pub/fedora/linux/releases/%version%/Cloud/x86_64/images/Fedora-Cloud-Base-%version%-1.2.x86_64.qcow2"
    "opensuse|openSUSE|yes|https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.%version%/images/openSUSE-Leap-15.%version%-OpenStack.x86_64.qcow2"
    "arch|Arch Linux|no|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
)

# Configuration directory for template configs
TEMPLATE_CONFIG_DIR="/etc/homelab/templates"
mkdir -p "$TEMPLATE_CONFIG_DIR"

# Handle CLI arguments
if [ "$1" = "--list-distros" ]; then
    echo "Available distributions:"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        echo "- $val: $desc (cloud-init: $ci)"
    done
    exit 0
fi

if [ "$1" = "--list-versions" ]; then
    distro="$2"
    case "$distro" in
        ubuntu)
            echo "Available Ubuntu versions: 22.04 (Jammy Jellyfish), 20.04 (Focal Fossa), 18.04 (Bionic Beaver)"
            ;;
        debian)
            echo "Available Debian versions: 12 (Bookworm), 11 (Bullseye), 10 (Buster)"
            ;;
        centos)
            echo "Available CentOS versions: 9 (Stream 9), 8 (Stream 8)"
            ;;
        rocky)
            echo "Available Rocky Linux versions: 9 (Rocky 9), 8 (Rocky 8)"
            ;;
        alpine)
            echo "Available Alpine versions: 3.19, 3.18, 3.17"
            ;;
        fedora)
            echo "Available Fedora versions: 39, 38, 37"
            ;;
        *)
            echo "Unknown distribution: $distro"
            exit 1
            ;;
    esac
    exit 0
fi

if [ "$1" = "--test" ]; then
    # Test mode - just display UI without executing VM creation
    TEST_MODE=1
fi

if [ "$1" = "--create" ]; then
    # Direct create mode - skip menu
    CREATE_MODE=1
fi

# Helper function to get distro URL template
get_distro_url_template() {
    local distro_id="$1"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        if [ "$val" = "$distro_id" ]; then
            echo "$url"
            return 0
        fi
    done
    echo ""
    return 1
}

# Helper function to check if distro supports cloud-init
supports_cloudinit() {
    local distro_id="$1"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        if [ "$val" = "$distro_id" ]; then
            if [ "$ci" = "yes" ]; then
                return 0
            else
                return 1
            fi
        fi
    done
    return 1
}

# Function to get predefined script templates
get_script_template() {
    local template_name="$1"

    case "$template_name" in
        "docker-setup")
            cat << 'EOF'
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
usermod -aG docker $(whoami)

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
EOF
            ;;
        "web-server")
            cat << 'EOF'
# Install and configure Nginx
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create basic index page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Server is ready!</h1>
    <p>This server was configured automatically with cloud-init.</p>
</body>
</html>
HTMLEOF

# Configure firewall
ufw --force enable
ufw allow ssh
ufw allow 'Nginx Full'
EOF
            ;;
        "security-hardening")
            cat << 'EOF'
# Basic security hardening
apt-get update && apt-get install -y fail2ban ufw

# Configure firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Disable root login and configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Set up automatic security updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
systemctl enable unattended-upgrades
EOF
            ;;
        "monitoring-agent")
            cat << 'EOF'
# Install Node Exporter for Prometheus monitoring
useradd --no-create-home --shell /bin/false node_exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*linux-amd64.tar.gz
tar -xzf node_exporter-*linux-amd64.tar.gz
cp node_exporter-*linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'SERVICEEOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
EOF
            ;;
        "dev-tools")
            cat << 'EOF'
# Install development tools
apt-get update
apt-get install -y git vim neovim tmux htop tree curl wget build-essential

# Install modern development tools
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Install Python development tools
apt-get install -y python3-pip python3-venv python3-dev

# Configure git (placeholder - users should customize)
# git config --global user.name "Your Name"
# git config --global user.email "your.email@example.com"
EOF
            ;;
        "auto-updates")
            cat << 'EOF'
# Configure automatic updates
apt-get update
apt-get install -y unattended-upgrades

# Configure automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'CONFEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONFEOF

# Configure what packages to update automatically
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'CONFEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONFEOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades
EOF
            ;;
        "custom-user")
            cat << 'EOF'
# Create additional system user
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy

# Set up SSH directory for deploy user
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chown deploy:deploy /home/deploy/.ssh

# Example: Copy authorized_keys (customize as needed)
# cp /home/*/. ssh/authorized_keys /home/deploy/.ssh/
# chown deploy:deploy /home/deploy/.ssh/authorized_keys
# chmod 600 /home/deploy/.ssh/authorized_keys
EOF
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

# Function to validate template configuration
validate_template_config() {
    local errors=()

    # Validate template name
    if [ -z "$template_name" ]; then
        errors+=("Template name is required")
    elif [[ ! "$template_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        errors+=("Template name contains invalid characters (only alphanumeric, underscore, and dash allowed)")
    fi

    # Validate distro selection
    if [ -z "$distro" ]; then
        errors+=("Distribution selection is required")
    fi

    # Set default values if not provided
    local cpu_value="${cpu:-2}"  # Default to 2 cores
    local ram_value="${ram:-2048}"  # Default to 2GB RAM
    local storage_value="${storage:-32}"  # Default to 32GB storage

    # Validate hardware specifications
    if ! [[ "$cpu_value" =~ ^[0-9]+$ ]] || [ "$cpu_value" -lt 1 ] || [ "$cpu_value" -gt 128 ]; then
        errors+=("CPU cores must be a number between 1 and 128")
    fi

    if ! [[ "$ram_value" =~ ^[0-9]+$ ]] || [ "$ram_value" -lt 512 ] || [ "$ram_value" -gt 131072 ]; then
        errors+=("RAM must be a number between 512 MB and 128 GB")
    fi

    if ! [[ "$storage_value" =~ ^[0-9]+$ ]] || [ "$storage_value" -lt 8 ] || [ "$storage_value" -gt 2048 ]; then
        errors+=("Storage must be a number between 8 GB and 2048 GB")
    fi

    # Validate cloud-init configuration if enabled
    if [ "$use_cloudinit" = "yes" ]; then
        if [ -z "$ci_user" ]; then
            errors+=("Cloud-init user is required when cloud-init is enabled")
        elif [[ ! "$ci_user" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            errors+=("Cloud-init username must start with a letter and contain only lowercase letters, numbers, underscore, and dash")
        fi

        # Validate static IP configuration
        if [ "$ci_network" != "dhcp" ] && [[ "$ci_network" == *"ip="* ]]; then
            local ip_part
            ip_part=$(echo "$ci_network" | grep -o 'ip=[^,]*' | cut -d'=' -f2)
            if [ -n "$ip_part" ] && ! [[ "$ip_part" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                errors+=("Invalid IP address format (expected CIDR notation like 192.168.1.100/24)")
            fi
        fi
    fi

    # Check if any errors were found
    if [ ${#errors[@]} -gt 0 ]; then
        local error_msg="Configuration errors found:\n\n"
        for error in "${errors[@]}"; do
            error_msg+="• $error\n"
        done

        whiptail --title "Configuration Errors" --msgbox "$error_msg\nPlease fix these errors and try again." 20 70
        return 1
    fi

    return 0
}

# Function to list all templates in Proxmox
list_templates() {
    log_info "Listing Proxmox templates..."

    # Get list of VMs that are templates
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid)|\(.name)|\(.status)|\(.maxmem//0)|\(.cpus//0)|\(.tags//"")"')

    if [ -z "$templates" ]; then
        whiptail --title "Templates" --msgbox "No templates found in Proxmox." 10 60
        return 0
    fi

    # Format templates for display
    local template_list=""
    local count=0
    while IFS='|' read -r vmid name status memory cpus tags; do
        if [ -n "$vmid" ]; then
            memory_gb=$(( memory / 1024 / 1024 ))
            template_list+="$vmid: $name (${memory_gb}GB RAM, ${cpus} CPU)\n"
            ((count++))
        fi
    done <<< "$templates"

    if [ $count -eq 0 ]; then
        whiptail --title "Templates" --msgbox "No templates found in Proxmox." 10 60
    else
        whiptail --title "Proxmox Templates ($count found)" --msgbox "$template_list" 20 80
    fi
}

# Function to manage existing templates
manage_templates() {
    while true; do
        local choice
        choice=$(whiptail --title "Template Management" --menu "Select an option:" 15 70 6 \
            "1" "List all templates" \
            "2" "View template details" \
            "3" "Delete template" \
            "4" "Clone template" \
            "5" "Template configuration" \
            "6" "Back to main menu" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                list_templates
                ;;
            2)
                view_template_details
                ;;
            3)
                delete_template
                ;;
            4)
                clone_template
                ;;
            5)
                manage_template_config
                ;;
            6|"")
                break
                ;;
        esac
    done
}

# Function to view template details
view_template_details() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Select Template" --menu "Choose template to view:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        # Get detailed template information
        local template_info
        template_info=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)

        local details=""
        details+="VMID: $selected_vmid\n"
        details+="Name: $(echo "$template_info" | jq -r '.name // "N/A"')\n"
        details+="Memory: $(echo "$template_info" | jq -r '.memory // "N/A"') MB\n"
        details+="CPU Cores: $(echo "$template_info" | jq -r '.cores // "N/A"')\n"
        details+="OS Type: $(echo "$template_info" | jq -r '.ostype // "N/A"')\n"
        details+="Description: $(echo "$template_info" | jq -r '.description // "N/A"')\n"
        details+="Tags: $(echo "$template_info" | jq -r '.tags // "None"')\n"
        details+="Boot Order: $(echo "$template_info" | jq -r '.boot // "N/A"')\n"

        whiptail --title "Template Details - VMID $selected_vmid" --msgbox "$details" 20 80
    fi
}

# Function to delete template
delete_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Delete Template" --menu "Choose template to delete:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        local template_name
        template_name=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json | jq -r '.name')

        if whiptail --title "Confirm Deletion" --yesno "Are you sure you want to delete template:\n\nVMID: $selected_vmid\nName: $template_name\n\nThis action cannot be undone!" 12 70; then
            if qm destroy "$selected_vmid"; then
                log_info "Template $selected_vmid ($template_name) deleted successfully"
                whiptail --title "Success" --msgbox "Template $selected_vmid ($template_name) deleted successfully!" 10 60
            else
                log_error "Failed to delete template $selected_vmid"
                whiptail --title "Error" --msgbox "Failed to delete template $selected_vmid. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to clone template
clone_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Clone Template" --menu "Choose template to clone:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        local new_name
        new_name=$(whiptail --title "Clone Template" --inputbox "Enter name for the new template:" 10 60 "template-clone-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)

        if [ -n "$new_name" ]; then
            local new_vmid
            new_vmid=$(pvesh get /cluster/nextid)

            if qm clone "$selected_vmid" "$new_vmid" --name "$new_name"; then
                if qm template "$new_vmid"; then
                    log_info "Template cloned successfully: $selected_vmid -> $new_vmid ($new_name)"
                    whiptail --title "Success" --msgbox "Template cloned successfully!\n\nOriginal: $selected_vmid\nNew: $new_vmid ($new_name)" 12 60
                else
                    log_error "Failed to convert cloned VM to template"
                    whiptail --title "Error" --msgbox "VM cloned but failed to convert to template. Check VMID $new_vmid manually." 10 60
                fi
            else
                log_error "Failed to clone template $selected_vmid"
                whiptail --title "Error" --msgbox "Failed to clone template $selected_vmid. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to manage template configuration files
manage_template_config() {
    while true; do
        local choice
        choice=$(whiptail --title "Template Configuration" --menu "Select an option:" 15 70 5 \
            "1" "Export template configuration" \
            "2" "Import template configuration" \
            "3" "List saved configurations" \
            "4" "Delete saved configuration" \
            "5" "Back to template management" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                export_template_config
                ;;
            2)
                import_template_config
                ;;
            3)
                list_saved_configs
                ;;
            4)
                delete_saved_config
                ;;
            5|"")
                break
                ;;
        esac
    done
}

# Function to export template configuration
export_template_config() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Export Configuration" --menu "Choose template to export:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        local config_name
        config_name=$(whiptail --title "Export Configuration" --inputbox "Enter name for the configuration file:" 10 60 "template-config-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)

        if [ -n "$config_name" ]; then
            local config_file="$TEMPLATE_CONFIG_DIR/${config_name}.json"
            local template_config
            template_config=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)

            # Create enhanced configuration with metadata
            local enhanced_config
            enhanced_config=$(cat << EOF
{
  "metadata": {
    "exported_date": "$(date -Iseconds)",
    "source_vmid": $selected_vmid,
    "config_name": "$config_name",
    "version": "1.0"
  },
  "proxmox_config": $template_config
}
EOF
)

            if echo "$enhanced_config" | jq '.' > "$config_file"; then
                log_info "Template configuration exported to $config_file"
                whiptail --title "Success" --msgbox "Template configuration exported successfully!\n\nFile: $config_file" 10 70
            else
                log_error "Failed to export template configuration"
                whiptail --title "Error" --msgbox "Failed to export template configuration. Check permissions." 10 60
            fi
        fi
    fi
}

# Function to import template configuration
import_template_config() {
    # List available configuration files
    local config_files=()
    while IFS= read -r -d '' file; do
        local basename_file
        basename_file=$(basename "$file" .json)
        config_files+=("$basename_file" "$(date -r "$file" '+%Y-%m-%d %H:%M')")
    done < <(find "$TEMPLATE_CONFIG_DIR" -name "*.json" -print0 2>/dev/null)

    if [ ${#config_files[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No saved configuration files found in $TEMPLATE_CONFIG_DIR." 10 70
        return 1
    fi

    local selected_config
    selected_config=$(whiptail --title "Import Configuration" --menu "Choose configuration to import:" 15 80 10 "${config_files[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_config" ]; then
        local config_file="$TEMPLATE_CONFIG_DIR/${selected_config}.json"
        local new_name
        new_name=$(whiptail --title "Import Configuration" --inputbox "Enter name for the new template:" 10 60 "imported-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)

        if [ -n "$new_name" ]; then
            # Get next available VMID
            local new_vmid
            new_vmid=$(pvesh get /cluster/nextid)

            # Extract configuration
            local config_data
            if ! config_data=$(jq -r '.proxmox_config' "$config_file"); then
                whiptail --title "Error" --msgbox "Failed to parse configuration file. File may be corrupted." 10 60
                return 1
            fi

            whiptail --title "Import Progress" --infobox "Creating VM from imported configuration...\nThis may take a few moments." 8 60

            # Create basic VM first
            local memory cores
            memory=$(echo "$config_data" | jq -r '.memory // 2048')
            cores=$(echo "$config_data" | jq -r '.cores // 2')

            if qm create "$new_vmid" --name "$new_name" --memory "$memory" --cores "$cores"; then
                # Apply additional configuration settings
                local ostype
                ostype=$(echo "$config_data" | jq -r '.ostype // "l26"')
                qm set "$new_vmid" --ostype "$ostype"

                # Set description
                local description="Imported from configuration: $selected_config\\nImported: $(date '+%Y-%m-%d %H:%M:%S')"
                qm set "$new_vmid" --description "$description"

                # Convert to template
                qm template "$new_vmid"

                log_info "Template imported successfully: VMID $new_vmid ($new_name)"
                whiptail --title "Success" --msgbox "Template imported successfully!\n\nVMID: $new_vmid\nName: $new_name\n\nNote: Disk images need to be restored separately." 12 70
            else
                log_error "Failed to create VM from imported configuration"
                whiptail --title "Error" --msgbox "Failed to create VM from imported configuration. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to list saved configuration files
list_saved_configs() {
    if [ ! -d "$TEMPLATE_CONFIG_DIR" ] || [ -z "$(ls -A "$TEMPLATE_CONFIG_DIR"/*.json 2>/dev/null)" ]; then
        whiptail --title "Saved Configurations" --msgbox "No saved configuration files found." 10 60
        return 0
    fi

    local config_list=""
    local count=0
    for file in "$TEMPLATE_CONFIG_DIR"/*.json; do
        if [ -f "$file" ]; then
            local basename_file
            basename_file=$(basename "$file" .json)
            local file_date
            file_date=$(date -r "$file" '+%Y-%m-%d %H:%M')
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            config_list+="$basename_file (${file_size}, $file_date)\n"
            ((count++))
        fi
    done

    whiptail --title "Saved Configurations ($count found)" --msgbox "$config_list" 20 80
}

# Function to delete saved configuration
delete_saved_config() {
    # List available configuration files
    local config_files=()
    while IFS= read -r -d '' file; do
        local basename_file
        basename_file=$(basename "$file" .json)
        config_files+=("$basename_file" "$(date -r "$file" '+%Y-%m-%d %H:%M')")
    done < <(find "$TEMPLATE_CONFIG_DIR" -name "*.json" -print0 2>/dev/null)

    if [ ${#config_files[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No saved configuration files found." 10 60
        return 1
    fi

    local selected_config
    selected_config=$(whiptail --title "Delete Configuration" --menu "Choose configuration to delete:" 15 80 10 "${config_files[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_config" ]; then
        if whiptail --title "Confirm Deletion" --yesno "Are you sure you want to delete configuration:\n\n$selected_config\n\nThis action cannot be undone!" 10 60; then
            local config_file="$TEMPLATE_CONFIG_DIR/${selected_config}.json"
            if rm -f "$config_file"; then
                log_info "Configuration file deleted: $config_file"
                whiptail --title "Success" --msgbox "Configuration file deleted successfully!" 10 60
            else
                log_error "Failed to delete configuration file: $config_file"
                whiptail --title "Error" --msgbox "Failed to delete configuration file. Check permissions." 10 60
            fi
        fi
    fi
}

# Function to validate existing template
validate_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found to validate." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Validate Template" --menu "Choose template to validate:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        whiptail --title "Validating" --infobox "Validating template $selected_vmid...\nPlease wait..." 8 50

        local validation_results=""
        local error_count=0
        local warning_count=0

        # Get template configuration
        local template_config
        template_config=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)

        # Validate template is actually a template
        local is_template
        is_template=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/status/current" --output-format=json | jq -r '.template // false')
        if [ "$is_template" != "true" ]; then
            validation_results+="❌ ERROR: VMID $selected_vmid is not marked as a template\n"
            ((error_count++))
        else
            validation_results+="✅ Template status: Valid\n"
        fi

        # Validate memory configuration
        local memory
        memory=$(echo "$template_config" | jq -r '.memory // 0')
        if [ "$memory" -lt 512 ]; then
            validation_results+="❌ ERROR: Memory too low ($memory MB, minimum 512 MB)\n"
            ((error_count++))
        elif [ "$memory" -lt 1024 ]; then
            validation_results+="⚠️  WARNING: Low memory allocation ($memory MB)\n"
            ((warning_count++))
        else
            validation_results+="✅ Memory: $memory MB (OK)\n"
        fi

        # Validate CPU configuration
        local cores
        cores=$(echo "$template_config" | jq -r '.cores // 0')
        if [ "$cores" -lt 1 ]; then
            validation_results+="❌ ERROR: No CPU cores assigned\n"
            ((error_count++))
        else
            validation_results+="✅ CPU Cores: $cores (OK)\n"
        fi

        # Check for storage configuration
        local has_storage=false
        for key in $(echo "$template_config" | jq -r 'keys[]'); do
            if [[ "$key" =~ ^(scsi|ide|sata|virtio)[0-9]+$ ]]; then
                has_storage=true
                validation_results+="✅ Storage: Found $key\n"
                break
            fi
        done
        if [ "$has_storage" = false ]; then
            validation_results+="❌ ERROR: No storage devices found\n"
            ((error_count++))
        fi

        # Check network configuration
        local has_network=false
        for key in $(echo "$template_config" | jq -r 'keys[]'); do
            if [[ "$key" =~ ^net[0-9]+$ ]]; then
                has_network=true
                validation_results+="✅ Network: Found $key\n"
                break
            fi
        done
        if [ "$has_network" = false ]; then
            validation_results+="⚠️  WARNING: No network interfaces configured\n"
            ((warning_count++))
        fi

        # Check cloud-init configuration
        local has_cloudinit
        has_cloudinit=$(echo "$template_config" | jq -r 'has("ide2")')
        if [ "$has_cloudinit" = "true" ]; then
            validation_results+="✅ Cloud-init: Configured\n"

            # Check cloud-init user
            local ci_user
            ci_user=$(echo "$template_config" | jq -r '.ciuser // "none"')
            if [ "$ci_user" != "none" ]; then
                validation_results+="✅ Cloud-init user: $ci_user\n"
            else
                validation_results+="⚠️  WARNING: Cloud-init enabled but no user configured\n"
                ((warning_count++))
            fi
        else
            validation_results+="ℹ️  Info: Cloud-init not configured\n"
        fi

        # Summary
        local status_summary=""
        if [ $error_count -eq 0 ]; then
            if [ $warning_count -eq 0 ]; then
                status_summary="✅ VALIDATION PASSED: Template is ready for use"
            else
                status_summary="⚠️  VALIDATION PASSED WITH WARNINGS: $warning_count warning(s) found"
            fi
        else
            status_summary="❌ VALIDATION FAILED: $error_count error(s), $warning_count warning(s)"
        fi

        validation_results+="\\n$status_summary"

        whiptail --title "Template Validation Results" --msgbox "$validation_results" 25 80

        log_info "Template validation completed for VMID $selected_vmid: $error_count errors, $warning_count warnings"
    fi
}

# Function to test template functionality
test_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')

    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found to test." 10 60
        return 1
    fi

    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"

    local selected_vmid
    selected_vmid=$(whiptail --title "Test Template" --menu "Choose template to test:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$selected_vmid" ]; then
        if whiptail --title "Template Testing" --yesno "This will create a temporary VM from the template for testing.\n\nThe VM will be created, started, tested, and then destroyed.\n\nProceed with testing?" 12 70; then
            whiptail --title "Testing" --infobox "Testing template $selected_vmid...\nCreating test VM..." 8 50

            # Get next available VMID for test VM
            local test_vmid
            test_vmid=$(pvesh get /cluster/nextid)

            # Clone template to test VM
            if qm clone "$selected_vmid" "$test_vmid" --name "test-$selected_vmid-$(date +%s)"; then
                log_info "Test VM $test_vmid created from template $selected_vmid"

                # Start the test VM
                whiptail --title "Testing" --infobox "Starting test VM $test_vmid...\nThis may take a moment..." 8 50

                if qm start "$test_vmid"; then
                    log_info "Test VM $test_vmid started successfully"

                    # Wait a moment for VM to start
                    sleep 10

                    # Check VM status
                    local vm_status
                    vm_status=$(qm status "$test_vmid")

                    local test_results="✅ Template cloning: SUCCESS\n✅ VM creation: SUCCESS\n✅ VM startup: SUCCESS\n\nVM Status: $vm_status\n"

                    # Test basic functionality
                    whiptail --title "Testing" --infobox "Testing VM functionality...\nChecking guest agent..." 8 50
                    sleep 5

                    # Check if guest agent is running (if configured)
                    if qm guest ping "$test_vmid" 2>/dev/null; then
                        test_results+="✅ Guest agent: RESPONDING\n"
                    else
                        test_results+="⚠️  Guest agent: NOT RESPONDING (may need more time or not configured)\n"
                    fi

                    # Stop the test VM
                    whiptail --title "Testing" --infobox "Stopping and cleaning up test VM..." 8 50
                    qm stop "$test_vmid"
                    sleep 5

                    # Destroy test VM
                    qm destroy "$test_vmid"

                    test_results+="\n✅ Test completed successfully\n✅ Test VM cleaned up"

                    whiptail --title "Template Test Results" --msgbox "$test_results" 20 70

                    log_info "Template test completed successfully for VMID $selected_vmid"
                else
                    log_error "Failed to start test VM $test_vmid"
                    qm destroy "$test_vmid"
                    whiptail --title "Test Failed" --msgbox "❌ Test failed: Could not start test VM\n\nTest VM has been cleaned up." 10 60
                fi
            else
                log_error "Failed to clone template $selected_vmid for testing"
                whiptail --title "Test Failed" --msgbox "❌ Test failed: Could not clone template for testing" 10 60
            fi
        fi
    fi
}

# Function to check required tools
check_dependencies() {
    local deps=(curl qemu-img whiptail jq)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        whiptail --title "Error" --msgbox "Missing required tools: ${missing[*]}\n\nPlease install these dependencies and try again." 10 70
        exit 1
    fi
}

# Check for Proxmox environment
check_proxmox() {
    if ! command -v pvesh &> /dev/null; then
        log_error "This script must be run in a Proxmox VE environment."
        whiptail --title "Error" --msgbox "This script must be run in a Proxmox VE environment." 10 60
        exit 1
    fi
}

# Run pre-checks
if [ -z "$TEST_MODE" ]; then
    check_dependencies
    check_proxmox
fi

# The first (older) show_help function definition (lines approx 930-948) is removed.
# The first (older) create_template function definition (lines approx 190-480) is removed.
# The script will now only use the more detailed create_template and show_help functions defined later.

# Helper function to show progress
show_progress() {
    local pid=$1
    local delay=0.5
    local spinstr='|/-\'
    local progress=""

    echo -n "  "  # Initial indent
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf "\r[%c] %s" "$spinstr" "$progress"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        progress=".$progress"
        # Keep progress from getting too long
        [ ${#progress} -gt 10 ] && progress=""
    done
    printf "\r%-20s\n" "[✓] Done"
}

# Function to validate template name
validate_template_name() {
    local name=$1
    # Check if name is empty
    if [ -z "$name" ]; then
        log_error "Template name cannot be empty"
        return 1
    fi
    # Check for invalid characters (only alphanumeric, hyphen, and underscore allowed)
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid template name. Only alphanumeric, hyphen, and underscore characters are allowed."
        return 1
    fi
    # Check if template with same name already exists
    if pvesh get /storage/local/content | grep -q "$name"; then
        log_error "A template with name '$name' already exists"
        return 1
    fi
    return 0
}

# Function to configure cloud-init
configure_cloud_init() {
    local distro=$1

    # Initialize cloud-init configuration
    local cloud_init_config=()

    # Check if distribution supports cloud-init
    if ! supports_cloudinit "$distro"; then
        log_info "Cloud-init is not supported for $distro"
        return 1
    fi

    # Ask if user wants to enable cloud-init
    if ! whiptail --title "Cloud-Init Configuration" --yesno "Enable cloud-init for this template?" 10 60; then
        log_info "Cloud-init disabled by user"
        return 1
    fi

    # Configure cloud-init user
    local ci_user
    while true; do
        ci_user=$(whiptail --title "Cloud-Init User" --inputbox "Enter default username:" 10 60 "clouduser" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled cloud-init configuration"; return 1; }

        # Validate username (starts with letter, only lowercase letters, numbers, underscore, dash)
        if [[ "$ci_user" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            break
        else
            whiptail --title "Invalid Username" --msgbox "Username must start with a letter and contain only lowercase letters, numbers, underscore, and dash" 10 60
        fi
    done

    # Configure password
    local password_ok=false
    local ci_password
    while [ "$password_ok" = false ]; do
        ci_password=$(whiptail --title "Cloud-Init Password" --passwordbox "Enter password for $ci_user:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled password setup"; return 1; }

        local password_verify=$(whiptail --title "Verify Password" --passwordbox "Re-enter password:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled password verification"; return 1; }

        if [ "$ci_password" = "$password_verify" ]; then
            password_ok=true
        else
            whiptail --title "Error" --msgbox "Passwords do not match. Please try again." 10 60
        fi
    done

    # Configure SSH keys
    local ssh_keys=""
    if whiptail --title "SSH Keys" --yesno "Would you like to add SSH public keys for passwordless login?" 10 60; then
        local key_file
        key_file=$(whiptail --title "SSH Public Key File" --inputbox "Enter path to SSH public key file:" 10 60 "$HOME/.ssh/id_rsa.pub" 3>&1 1>&2 2>&3)

        if [ -f "$key_file" ]; then
            ssh_keys=$(cat "$key_file")
            log_info "Added SSH key from $key_file"
        else
            log_warn "SSH key file not found: $key_file"
            whiptail --title "Warning" --msgbox "SSH key file not found. You can add keys later." 10 60
        fi
    fi

    # Configure network (DHCP by default)
    local network_config=""
    if whiptail --title "Network Configuration" --yesno "Configure static IP? (No for DHCP)" 10 60; then
        local ip_address netmask gateway dns

        ip_address=$(whiptail --title "IP Address" --inputbox "Enter IP address (e.g., 192.168.1.100):" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled network configuration"; return 1; }

        netmask=$(whiptail --title "Netmask" --inputbox "Enter netmask (e.g., 255.255.255.0):" 10 60 "255.255.255.0" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled network configuration"; return 1; }

        gateway=$(whiptail --title "Gateway" --inputbox "Enter default gateway:" 10 60 "${ip_address%.*}.1" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled network configuration"; return 1; }

        dns=$(whiptail --title "DNS Servers" --inputbox "Enter DNS servers (comma-separated):" 10 60 "8.8.8.8,8.8.4.4" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled network configuration"; return 1; }

        network_config="\n  network:"
        network_config+="\n    version: 2"
        network_config+="\n    ethernets:"
        network_config+="\n      eth0:"
        network_config+="\n        dhcp4: false"
        network_config+="\n        addresses: [$ip_address/$(ipcalc -p $ip_address $netmask | cut -d= -f2)]"
        network_config+="\n        gateway4: $gateway"
        network_config+="\n        nameservers:"
        network_config+="\n          addresses: [${dns//,/ }]"
    fi

    # Configure timezone
    local timezone
    timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    timezone=$(whiptail --title "Timezone" --inputbox "Enter timezone:" 10 60 "$timezone" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled timezone configuration"; return 1; }

    # Configure hostname
    local hostname
    hostname=$(whiptail --title "Hostname" --inputbox "Enter hostname:" 10 60 "$template_name" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled hostname configuration"; return 1; }

    # Build cloud-init configuration
    local user_data="#cloud-config\n"
    user_data+="hostname: $hostname\n"
    user_data+="fqdn: $hostname.localdomain\n"
    user_data+="manage_etc_hosts: true\n"
    user_data+="timezone: $timezone\n"

    # User configuration
    user_data+="\nusers:\n"
    user_data+="  - name: $ci_user\n"
    user_data+="    sudo: ALL=(ALL) NOPASSWD:ALL\n"
    user_data+="    shell: /bin/bash\n"

    if [ -n "$ssh_keys" ]; then
        user_data+="    ssh_authorized_keys:\n"
        user_data+="      - $ssh_keys\n"
    fi

    # Password configuration
    user_data+="\nchpasswd:\n"
    user_data+="  list: |\n"
    user_data+="    $ci_user:$ci_password\n"
    user_data+="  expire: false\n"

    # Package update and upgrade
    user_data+="\npackage_update: true\n"
    user_data+="package_upgrade: true\n"

    # Add network configuration if specified
    if [ -n "$network_config" ]; then
        user_data+="$network_config\n"
    fi

    # Write cloud-init configuration to a temporary file
    local temp_dir=$(mktemp -d)
    echo -e "$user_data" > "$temp_dir/user-data"

    # Generate meta-data
    echo "instance-id: $(uuidgen || echo "i-$(date +%s)")" > "$temp_dir/meta-data"

    # Create cloud-init ISO
    local ci_iso_path="/var/lib/vz/template/cloud-init/$template_name-cloud-init.iso"
    mkdir -p "$(dirname "$ci_iso_path")"

    genisoimage -output "$ci_iso_path" -volid cidata -joliet -rock \
        "$temp_dir/user-data" "$temp_dir/meta-data" >/dev/null 2>&1 &
    local gen_iso_pid=$!
    show_progress $gen_iso_pid

    # Clean up temporary files
    rm -rf "$temp_dir"

    # Return the path to the cloud-init ISO
    echo "$ci_iso_path"
    return 0
}

# Function to configure VM resources (CPU, memory, disk)
configure_vm_resources() {
    local vm_id=$1

    # Get current VM configuration
    local current_config=$(qm config $vm_id 2>/dev/null)

    # Default values
    local default_cores=2
    local default_memory=2048
    local default_disk_size="32G"
    local default_disk_storage="local-lvm"

    # Parse current configuration if exists
    if [ -n "$current_config" ]; then
        default_cores=$(echo "$current_config" | grep -oP 'cores \K\d+' || echo "2")
        default_memory=$(echo "$current_config" | grep -oP 'memory \K\d+' || echo "2048")
        default_disk_size=$(echo "$current_config" | grep -oP 'size=\K[^ ]+' | head -1 || echo "32G")
        default_disk_storage=$(echo "$current_config" | grep -oP 'scsi0: \K[^,]+' | cut -d: -f1 || echo "local-lvm")
    fi

    # Configure CPU cores
    local cores
    cores=$(whiptail --title "CPU Cores" --inputbox "Number of CPU cores:" 10 60 "$default_cores" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled CPU configuration"; return 1; }

    # Validate CPU cores
    if ! [[ "$cores" =~ ^[1-9][0-9]*$ ]]; then
        whiptail --title "Invalid Input" --msgbox "CPU cores must be a positive integer." 10 60
        return 1
    fi

    # Configure memory (in MB)
    local memory
    memory=$(whiptail --title "Memory (MB)" --inputbox "Amount of memory in MB:" 10 60 "$default_memory" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled memory configuration"; return 1; }

    # Validate memory
    if ! [[ "$memory" =~ ^[1-9][0-9]*$ ]]; then
        whiptail --title "Invalid Input" --msgbox "Memory must be a positive integer (in MB)." 10 60
        return 1
    fi

    # Configure disk size
    local disk_size
    disk_size=$(whiptail --title "Disk Size" --inputbox "Disk size (e.g., 32G, 100G):" 10 60 "$default_disk_size" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled disk size configuration"; return 1; }

    # Validate disk size format
    if ! [[ "$disk_size" =~ ^[0-9]+[KMGTP]$ ]]; then
        whiptail --title "Invalid Input" --msgbox "Invalid disk size format. Use format like 32G, 100G, etc." 10 60
        return 1
    fi

    # Get available storage (using mapfile to avoid splitting issues)
    local storage_list=()
    local storage_output
    storage_output=$(pvesm status --enabled --type dir,lvm,iscsi,cephfs,nfs,cifs 2>/dev/null || true)
    if [ -n "$storage_output" ]; then
        mapfile -t storage_list < <(echo "$storage_output" | awk 'NR>1 {print $1}')
    fi
    if [ ${#storage_list[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No storage available. Please configure storage in Proxmox first." 10 60
        return 1
    fi

    # Create storage menu
    local storage_menu=()
    for storage in "${storage_list[@]}"; do
        if [ "$storage" = "$default_disk_storage" ]; then
            storage_menu+=("$storage" "" "ON")
        else
            storage_menu+=("$storage" "" "OFF")
        fi
    done

    # Select storage
    local disk_storage
    disk_storage=$(whiptail --title "Select Storage" --radiolist \
        "Select storage for the disk:" 15 60 5 "${storage_menu[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled storage selection"; return 1; }

    # Return configuration
    echo "$cores $memory $disk_size $disk_storage"
    return 0
}

# Function to configure network settings
configure_network() {
    local vm_id=$1
    local default_bridge="vmbr0"

    # Get current network configuration
    local current_config=$(qm config $vm_id 2>/dev/null | grep -E '^net[0-9]+:' | head -1 || echo "")

    # Parse current configuration if exists
    if [ -n "$current_config" ]; then
        default_bridge=$(echo "$current_config" | grep -oP 'bridge=\K[^,]+' || echo "vmbr0")
    fi

    # Get available bridges (using glob and array instead of ls | grep)
    local bridge_list=()
    for iface in /sys/class/net/*; do
        if [ "$(basename "$iface")" != "lo" ]; then
            bridge_list+=("$(basename "$iface")")
        fi
    done
    if [ ${#bridge_list[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No network bridges found. Please configure networking in Proxmox first." 10 60
        return 1
    fi

    # Create bridge menu
    local bridge_menu=()
    for bridge in "${bridge_list[@]}"; do
        if [ "$bridge" = "$default_bridge" ]; then
            bridge_menu+=("$bridge" "" "ON")
        else
            bridge_menu+=("$bridge" "" "OFF")
        fi
    done

    # Select bridge
    local selected_bridge
    selected_bridge=$(whiptail --title "Select Network Bridge" --radiolist \
        "Select network bridge for the VM:" 15 60 5 "${bridge_menu[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled network configuration"; return 1; }

    # Configure network model
    local model_menu=(
        "virtio" "VirtIO (Recommended for Linux)" "ON"
        "e1000" "Intel E1000" "OFF"
        "rtl8139" "Realtek RTL8139" "OFF"
        "vmxnet3" "VMware vmxnet3" "OFF"
    )

    local selected_model
    selected_model=$(whiptail --title "Select Network Model" --radiolist \
        "Select network interface model:" 15 60 5 "${model_menu[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled network model selection"; return 1; }

    # Configure VLAN (optional)
    local vlan_tag=""
    if whiptail --title "VLAN Configuration" --yesno "Configure VLAN tag?" 10 60; then
        vlan_tag=$(whiptail --title "VLAN Tag" --inputbox "Enter VLAN ID (1-4094):" 10 60 "" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled VLAN configuration"; return 1; }

        # Validate VLAN ID
        if ! [[ "$vlan_tag" =~ ^[1-9][0-9]{0,3}$ ]] || [ "$vlan_tag" -gt 4094 ]; then
            whiptail --title "Invalid Input" --msgbox "VLAN ID must be between 1 and 4094." 10 60
            return 1
        fi
    fi

    # Return configuration
    echo "$selected_bridge $selected_model $vlan_tag"
    return 0
}

# Function to create a new VM
create_vm() {
    local vm_id=$1
    local name=$2
    local cores=$3
    local memory=$4
    local disk_size=$5
    local disk_storage=$6
    local bridge=$7
    local model=$8
    local vlan_tag=$9
    local ci_iso_path=${10}

    log_info "Creating VM $vm_id ($name) with $cores cores, ${memory}MB RAM, ${disk_size} disk"

    # Create VM
    if ! qm create $vm_id --name "$name" --memory $memory --cores $cores --net0 $model,bridge=$bridge${vlan_tag:+,tag=$vlan_tag}; then
        log_error "Failed to create VM $vm_id"
        return 1
    fi

    # Attach disk
    if ! qm set $vm_id --scsihw virtio-scsi-pci --scsi0 $disk_storage:0,import-from=$disk_storage:$disk_size; then
        log_error "Failed to attach disk to VM $vm_id"
        qm destroy $vm_id --purge
        return 1
    fi

    # Attach cloud-init ISO if provided
    if [ -n "$ci_iso_path" ] && [ -f "$ci_iso_path" ]; then
        if ! qm set $vm_id --ide2 $disk_storage:cloudinit; then
            log_warn "Failed to attach cloud-init drive to VM $vm_id"
        fi

        # Mount cloud-init ISO
        if ! qm set $vm_id --ide3 $ci_iso_path,media=cdrom; then
            log_warn "Failed to mount cloud-init ISO to VM $vm_id"
        fi
    fi

    # Set boot order
    if ! qm set $vm_id --boot c --bootdisk scsi0; then
        log_warn "Failed to set boot order for VM $vm_id"
    fi

    # Enable QEMU guest agent
    if ! qm set $vm_id --agent enabled=1; then
        log_warn "Failed to enable QEMU guest agent for VM $vm_id"
    fi

    return 0
}

# Main template creation function
create_template() {
    log_info "Starting template creation wizard"

    # --- Step 1: Template Name ---
    while true; do
        template_name=$(whiptail --title "Template Name" --inputbox "Enter a name for the new VM template:" 10 60 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled template creation"; return 0; }

        if validate_template_name "$template_name"; then
            break
        else
            whiptail --title "Invalid Name" --msgbox "Please enter a valid template name (alphanumeric, hyphen, underscore only)" 10 60
        fi
    done

    # --- Step 2: Source Type Selection ---
    local source_type
    source_type=$(whiptail --title "Source Type" --menu "Select Source Type:" 15 70 3 \
        "predefined" "Predefined Cloud Image" \
        "custom" "Custom ISO/Image from Proxmox Storage" \
        "cancel" "Cancel Template Creation" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ "$source_type" = "cancel" ] || [ -z "$source_type" ]; then
        log_info "User cancelled at source type selection."
        return 0
    fi

    # Initialize variables
    local distro="" version=""
    local custom_source_storage="" custom_source_path="" custom_file_type=""
    local ci_iso_path=""
    local ci_config_type="default"

    # --- Step 3: Get VM ID ---
    local next_vm_id=100
    local used_ids
    mapfile -t used_ids < <(qm list --full | awk 'NR>1 {print $1}')

    # Check if next_vm_id is already used
    local id_in_use=1
    while [ $id_in_use -eq 1 ]; do
        id_in_use=0
        for id in "${used_ids[@]}"; do
            if [ "$id" = "$next_vm_id" ]; then
                id_in_use=1
                ((next_vm_id++))
                break
            fi
        done
    done

    local vm_id
    vm_id=$(whiptail --title "VM ID" --inputbox "Enter VM ID:" 10 60 "$next_vm_id" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { log_info "User cancelled VM ID selection"; return 0; }

    # Validate VM ID
    if ! [[ "$vm_id" =~ ^[0-9]+$ ]]; then
        whiptail --title "Invalid VM ID" --msgbox "VM ID must be a number." 10 60
        return 1
    fi

    # Check if VM ID is already in use
    local id_in_use=0
    for id in "${used_ids[@]}"; do
        if [ "$id" = "$vm_id" ]; then
            id_in_use=1
            break
        fi
    done

    if [ $id_in_use -eq 1 ]; then
        whiptail --title "VM ID In Use" --msgbox "VM ID $vm_id is already in use." 10 60
        return 1
    fi

    # --- Step 4: Configure VM Resources ---
    local vm_config
    vm_config=$(configure_vm_resources $vm_id)
    [ $? -ne 0 ] && return 1

    # Parse VM configuration
    local cores memory disk_size disk_storage
    read -r cores memory disk_size disk_storage <<< "$vm_config"

    # --- Step 5: Configure Network ---
    local network_config
    network_config=$(configure_network $vm_id)
    [ $? -ne 0 ] && return 1

    # Parse network configuration
    local bridge model vlan_tag
    read -r bridge model vlan_tag <<< "$network_config"

    # --- Step 6: Cloud-Init Configuration ---
    if whiptail --title "Cloud-Init" --yesno "Configure cloud-init for this template?" 10 60; then
        ci_iso_path=$(configure_cloud_init "$distro")
        [ $? -ne 0 ] && { log_info "Cloud-init configuration cancelled"; return 1; }
    fi

    # --- Step 7: Distribution Selection (only for predefined images) ---
    if [ "$source_type" = "predefined" ]; then
        local distro_menu=()
        for entry in "${DISTRO_LIST[@]}"; do
            IFS='|' read -r val desc ci url <<< "$entry"
            distro_menu+=("$val" "$desc")
        done

        distro=$(whiptail --title "Select Distribution" --menu "Choose a Linux distribution:" 20 60 10 "${distro_menu[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled at distro selection"; return 0; }
    fi

    # --- Step 8: Version Selection (only for predefined images) ---
    if [ "$source_type" = "predefined" ]; then
        case "$distro" in
            ubuntu)
                version=$(whiptail --title "Ubuntu Version" --menu "Select Ubuntu version:" 15 60 5 \
                    "22.04" "Jammy Jellyfish (LTS)" \
                    "20.04" "Focal Fossa (LTS)" \
                    "18.04" "Bionic Beaver (LTS)" 3>&1 1>&2 2>&3)
                ;;
            debian)
                version=$(whiptail --title "Debian Version" --menu "Select Debian version:" 15 60 5 \
                    "12" "Bookworm" \
                    "11" "Bullseye" \
                    "10" "Buster" 3>&1 1>&2 2>&3)
                ;;
            centos)
                version=$(whiptail --title "CentOS Version" --menu "Select CentOS version:" 15 60 5 \
                    "9" "Stream 9" \
                    "8" "Stream 8" 3>&1 1>&2 2>&3)
                ;;
            rocky)
                version=$(whiptail --title "Rocky Linux Version" --menu "Select Rocky Linux version:" 15 60 5 \
                    "9" "Rocky 9" \
                    "8" "Rocky 8" 3>&1 1>&2 2>&3)
                ;;
            alpine)
                version=$(whiptail --title "Alpine Version" --menu "Select Alpine version:" 15 60 5 \
                    "3.19" "Alpine 3.19" \
                    "3.18" "Alpine 3.18" \
                    "3.17" "Alpine 3.17" 3>&1 1>&2 2>&3)
                ;;
            fedora)
                version=$(whiptail --title "Fedora Version" --menu "Select Fedora version:" 15 60 5 \
                    "39" "Fedora 39" \
                    "38" "Fedora 38" \
                    "37" "Fedora 37" 3>&1 1>&2 2>&3)
                ;;
            opensuse)
                version=$(whiptail --title "openSUSE Version" --menu "Select openSUSE version:" 15 60 5 \
                    "4" "Leap 15.4" \
                    "3" "Leap 15.3" 3>&1 1>&2 2>&3)
                ;;
            *)
                version="latest"
                ;;
        esac

        [ $? -ne 0 ] && { log_info "User cancelled at version selection"; return 0; }

        # --- Step 9: Download Predefined Image ---
        local image_url
        image_url=$(get_distro_url_template "$distro" "$version")
        if [ -z "$image_url" ]; then
            whiptail --title "Error" --msgbox "Failed to get download URL for $distro $version" 10 60
            return 1
        fi

        local image_name="${distro}-${version}-cloudimg-amd64.img"
        local image_path="/var/lib/vz/template/iso/${image_name}"

        log_info "Downloading $distro $version image..."
        if ! wget -q --show-progress -O "$image_path" "$image_url"; then
            whiptail --title "Error" --msgbox "Failed to download $distro $version image" 10 60
            return 1
        fi

        custom_source_path="$image_path"
        custom_file_type="qcow2"
    else
        # --- Step 9: Custom Image Selection ---
        local storage_list=()
        mapfile -t storage_list < <(pvesm status --enabled --type dir,lvm,iscsi,cephfs,nfs,cifs | awk 'NR>1 {print $1}')

        if [ ${#storage_list[@]} -eq 0 ]; then
            whiptail --title "Error" --msgbox "No storage available. Please configure storage in Proxmox first." 10 60
            return 1
        fi

        # Create storage menu
        local storage_menu=()
        for storage in "${storage_list[@]}"; do
            storage_menu+=("$storage" "")
        done

        # Select storage
        local selected_storage
        selected_storage=$(whiptail --title "Select Storage" --menu "Select storage containing the image:" 15 60 5 "${storage_menu[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled storage selection"; return 1; }

        # Get list of files in storage
        local file_list=()
        mapfile -t file_list < <(pvesm list "$selected_storage" | awk 'NR>1 {print $1}')

        if [ ${#file_list[@]} -eq 0 ]; then
            whiptail --title "Error" --msgbox "No files found in selected storage." 10 60
            return 1
        fi

        # Create file menu
        local file_menu=()
        for file in "${file_list[@]}"; do
            file_menu+=("$file" "")
        done

        # Select file
        custom_source_path=$(whiptail --title "Select File" --menu "Select image file:" 20 80 10 "${file_menu[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && { log_info "User cancelled file selection"; return 1; }

        # Determine file type
        custom_file_type=$(qemu-img info "$selected_storage:$custom_source_path" 2>/dev/null | grep 'file format' | awk '{print $3}' || echo "unknown")
        if [ "$custom_file_type" = "unknown" ]; then
            whiptail --title "Warning" --msgbox "Could not determine image type. Defaulting to raw format." 10 60
            custom_file_type="raw"
        fi
    fi

    # --- Step 10: Create VM ---
    if ! create_vm "$vm_id" "$template_name" "$cores" "$memory" "$disk_size" "$disk_storage" \
        "$bridge" "$model" "$vlan_tag" "$ci_iso_path"; then
        whiptail --title "Error" --msgbox "Failed to create VM $vm_id" 10 60
        return 1
    fi

    # --- Step 11: Import Disk ---
    log_info "Importing disk image..."
    if [ "$source_type" = "predefined" ]; then
        if ! qm importdisk "$vm_id" "$custom_source_path" "$disk_storage" --format qcow2; then
            log_error "Failed to import disk image"
            qm destroy "$vm_id" --purge
            return 1
        fi
    else
        if ! qm importdisk "$vm_id" "$selected_storage:$custom_source_path" "$disk_storage" --format "$custom_file_type"; then
            log_error "Failed to import disk image"
            qm destroy "$vm_id" --purge
            return 1
        fi
    fi

    # --- Step 12: Configure VM ---
    log_info "Configuring VM..."

    # Set boot order
    if ! qm set "$vm_id" --boot c --bootdisk scsi0; then
        log_warn "Failed to set boot order"
    fi

    # Enable QEMU agent
    if ! qm set "$vm_id" --agent enabled=1; then
        log_warn "Failed to enable QEMU agent"
    fi

    # Set display to serial console
    if ! qm set "$vm_id" --serial0 socket --vga serial0; then
        log_warn "Failed to configure serial console"
    fi

    # --- Step 13: Convert to Template ---
    if whiptail --title "Convert to Template" --yesno "Convert VM to template after creation?" 10 60; then
        log_info "Converting VM $vm_id to template..."
        if ! qm template "$vm_id"; then
            log_error "Failed to convert VM to template"
            return 1
        fi
        whiptail --title "Success" --msgbox "Template '$template_name' (ID: $vm_id) created successfully!" 10 60
    else
        whiptail --title "Success" --msgbox "VM '$template_name' (ID: $vm_id) created successfully!" 10 60
    fi

    log_info "Template creation completed successfully"
    return 0
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Proxmox Template Creator" --menu "Select an option:" 20 70 8 \
            "1" "Create new template" \
            "2" "List all templates" \
            "3" "Manage existing templates" \
            "4" "Validate template" \
            "5" "Test template" \
            "6" "Template configuration management" \
            "7" "Help and documentation" \
            "8" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                create_template
                ;;
            2)
                list_templates
                ;;
            3)
                manage_templates
                ;;
            4)
                validate_template
                ;;
            5)
                test_template
                ;;
            6)
                manage_template_config
                ;;
            7)
                show_help
                ;;
            8|"")
                log_info "Exiting template creator"
                exit 0
                ;;
        esac
    done
}

# Check if running in direct create mode or as CLI arguments
if [ "$1" = "--create" ] || [ -n "$CREATE_MODE" ]; then
    # Run pre-checks and go directly to template creation
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    create_template
    exit $?
elif [ $# -eq 0 ]; then
    # No arguments provided, show main menu
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    main_menu
else
    # Arguments were provided and handled at the beginning of the script
    # This handles --list-distros, --list-versions, --test, etc.
    log_info "CLI arguments were processed at script start"
fi
                    rm -f "$tmp_paste_file"
                fi
            fi # End of if [ "$use_cloudinit" = "yes" ] after config type choice

            # Only proceed to default guided setup if ci_config_type is "default" AND cloud-init is still enabled
            if [ "$use_cloudinit" = "yes" ] && [ "$ci_config_type" = "default" ]; then
                ci_user=$(whiptail --title "Cloud-Init User" --inputbox "Enter default username:" 10 60 "clouduser" 3>&1 1>&2 2>&3)
                ci_user_result=$?
                if [ $ci_user_result -ne 0 ]; then return 0; fi

                # Default to SSH key in ~/.ssh/id_rsa.pub if exists
                default_key=""
                if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
                    default_key=$(cat "$HOME/.ssh/id_rsa.pub")
                fi

                ci_sshkey=$(whiptail --title "SSH Public Key" --inputbox "Paste SSH public key for user $ci_user:" 10 60 "$default_key" 3>&1 1>&2 2>&3)
                ci_sshkey_result=$?
                if [ $ci_sshkey_result -ne 0 ]; then return 0; fi

                # Validate SSH key format
                if [ -n "$ci_sshkey" ]; then
                    if ! echo "$ci_sshkey" | grep -E '^(ssh-rsa|ssh-ed25519|ssh-ecdsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]' >/dev/null; then
                        if ! whiptail --title "Invalid SSH Key" --yesno "The SSH key format appears invalid. Continue anyway?" 10 60; then
                            return 0
                        fi
                    else
                        log_info "SSH key format validation passed"
                    fi
                fi

                # Cloud-init password configuration
                ci_password=""
                ci_password_enabled="no"
                if whiptail --title "Password Authentication" --yesno "Do you want to enable password authentication for user $ci_user?\n\nNote: SSH key authentication is recommended for better security." 12 70; then
                    ci_password_enabled="yes"

                    # Get minimum password length from config (default 12)
                    min_length=12
                    # Assuming config.sh is in the parent directory of SCRIPT_DIR (e.g. scripts/../config.sh)
                    # This path might need adjustment if config.sh is elsewhere.
                    config_sh_path="$SCRIPT_DIR/../config.sh"
                    if [ -f "$config_sh_path" ] && command -v source >/dev/null 2>&1; then
                        min_length=$(grep "^MIN_PASSWORD_LENGTH=" "$config_sh_path" 2>/dev/null | cut -d'=' -f2 || echo "12")
                    fi

                    while true; do
                        ci_password=$(whiptail --title "Set Password" --passwordbox "Enter password for user $ci_user (minimum $min_length characters):" 12 60 3>&1 1>&2 2>&3)
                        ci_password_result=$?
                        if [ $ci_password_result -ne 0 ]; then
                            ci_password_enabled="no"
                            break
                        fi

                        # Validate password length
                        if [ ${#ci_password} -lt $min_length ]; then
                            whiptail --title "Password Too Short" --msgbox "Password must be at least $min_length characters long. Please try again." 10 60
                            continue
                        fi

                        # Confirm password
                        ci_password_confirm=$(whiptail --title "Confirm Password" --passwordbox "Confirm password for user $ci_user:" 10 60 3>&1 1>&2 2>&3)
                        if [ $? -ne 0 ]; then
                            ci_password_enabled="no"
                            break
                        fi

                        if [ "$ci_password" = "$ci_password_confirm" ]; then
                            log_info "Password authentication configured for user $ci_user"
                            break
                        else
                            whiptail --title "Password Mismatch" --msgbox "Passwords do not match. Please try again." 10 60
                        fi
                    done
                fi

                ci_network=$(whiptail --title "Network Config" --menu "Select network configuration:" 15 60 3 \
                    "dhcp" "Automatic IP configuration (DHCP)" \
                    "static" "Manual IP configuration" 3>&1 1>&2 2>&3)
                ci_network_result=$?
                if [ $ci_network_result -ne 0 ]; then return 0; fi

                if [ "$ci_network" = "static" ]; then
                    ci_ip=$(whiptail --title "Static IP" --inputbox "Enter IP address (CIDR format, e.g., 192.168.1.100/24):" 10 60 "" 3>&1 1>&2 2>&3)
                    ci_ip_result=$?
                    if [ $ci_ip_result -ne 0 ]; then return 0; fi

                    ci_gw=$(whiptail --title "Gateway" --inputbox "Enter default gateway:" 10 60 "" 3>&1 1>&2 2>&3)
                    ci_gw_result=$?
                    if [ $ci_gw_result -ne 0 ]; then return 0; fi

                    ci_nameserver=$(whiptail --title "DNS" --inputbox "Enter DNS server(s) (comma-separated):" 10 60 "1.1.1.1,8.8.8.8" 3>&1 1>&2 2>&3)
                    ci_nameserver_result=$?
                    if [ $ci_nameserver_result -ne 0 ]; then return 0; fi

                    ci_network="ip=$ci_ip,gw=$ci_gw,nameserver=$ci_nameserver"
                fi

                # --- Step 6: Package Pre-installation (Cloud-init only, moved into default block) ---
                install_packages=""
                # This inner if [ "$use_cloudinit" = "yes" ] is redundant if this whole block is already inside such a check.
                # However, keeping it for now to minimize changes to the moved block itself.
                if [ "$use_cloudinit" = "yes" ]; then
                    if whiptail --title "Package Installation" --yesno "Do you want to pre-install packages via cloud-init?" 10 60; then
                        # Package categories
                        PACKAGE_CATEGORIES=(
                            "essential" "Essential tools (curl, wget, vim, htop)" OFF
                            "docker" "Docker and Docker Compose" OFF
                            "development" "Development tools (git, build-essential)" OFF
                            "monitoring" "Monitoring agents (node-exporter)" OFF
                            "security" "Security tools (fail2ban, ufw)" OFF
                            "custom" "Custom package list" OFF
                        )

                        selected_packages=$(whiptail --title "Select Package Categories" --checklist "Choose packages to install:" 20 70 6 "${PACKAGE_CATEGORIES[@]}" 3>&1 1>&2 2>&3)
                        if [ $? -eq 0 ]; then
                            # Build package list based on selections
                            packages=()
                            for category in $selected_packages; do
                                category=$(echo "$category" | tr -d '"')
                                case "$category" in
                                    essential)
                                        packages+=(curl wget vim htop tree unzip)
                                        ;;
                                    docker)
                                        packages+=(docker.io docker-compose)
                                        ;;
                                    development)
                                        packages+=(git build-essential)
                                        ;;
                                    monitoring)
                                        packages+=(prometheus-node-exporter)
                                        ;;
                                    security)
                                        packages+=(fail2ban ufw)
                                        ;;
                                    custom)
                                        custom_packages=$(whiptail --title "Custom Packages" --inputbox "Enter package names (space-separated):" 10 60 "" 3>&1 1>&2 2>&3)
                                        if [ -n "$custom_packages" ]; then
                                            read -ra custom_array <<< "$custom_packages"
                                            packages+=("${custom_array[@]}")
                                        fi
                                        ;;
                                esac
                            done

                            if [ ${#packages[@]} -gt 0 ]; then
                                install_packages=$(IFS=' '; echo "${packages[*]}")
                                log_info "Packages to install: $install_packages"
                            fi
                        fi
                    fi
                fi

                # --- Step 6.5: Custom Script Execution (Cloud-init only, moved into default block) ---
                custom_scripts=""
                # This inner if [ "$use_cloudinit" = "yes" ] is redundant.
                if [ "$use_cloudinit" = "yes" ]; then
                    if whiptail --title "Custom Scripts" --yesno "Do you want to add custom scripts to run during first boot?" 10 60; then
                        # Script execution options
                        script_option=$(whiptail --title "Script Options" --menu "Choose script input method:" 15 70 4 \
                            "commands" "Simple commands (one per line)" \
                            "script" "Custom multi-line script" \
                            "template" "Predefined script templates" \
                            "none" "Skip custom scripts" 3>&1 1>&2 2>&3)

                        if [ "$script_option" != "none" ] && command -v "$script_option" >/dev/null 2>&1; then
                            case "$script_option" in
                                "commands")
                                    custom_scripts=$(whiptail --title "Custom Commands" --inputbox "Enter commands (one per line, use \\n for newlines):" 15 70 "" 3>&1 1>&2 2>&3)
                                    if [ $? -eq 0 ] && [ -n "$custom_scripts" ]; then
                                        # Convert \n to actual newlines
                                        custom_scripts=$(echo -e "$custom_scripts")
                                        log_info "Custom commands configured"
                                    fi
                                    ;;
                                "script")
                                    # Use a temporary file for multi-line script input
                                    SCRIPT_INPUT_FILE=$(mktemp)
                                    if whiptail --title "Custom Script" --textbox /dev/null 20 80 --scrolltext 2>"$SCRIPT_INPUT_FILE"; then
                                        if [ -s "$SCRIPT_INPUT_FILE" ]; then
                                            custom_scripts=$(cat "$SCRIPT_INPUT_FILE")
                                            log_info "Custom script configured"
                                        fi
                                    fi
                                    rm -f "$SCRIPT_INPUT_FILE"
                                    ;;
                                "template")
                                    # Predefined script templates
                                    template_choice=$(whiptail --title "Script Templates" --menu "Choose a predefined script template:" 18 80 8 \
                                        "docker-setup" "Install and configure Docker" \
                                        "web-server" "Basic web server setup (nginx)" \
                                        "security-hardening" "Basic security hardening" \
                                        "monitoring-agent" "Install monitoring agents" \
                                        "dev-tools" "Development tools setup" \
                                        "auto-updates" "Configure automatic updates" \
                                        "custom-user" "Create additional system user" \
                                        "none" "Cancel template selection" 3>&1 1>&2 2>&3)

                                    if [ "$template_choice" != "none" ] && [ -n "$template_choice" ]; then
                                        custom_scripts=$(get_script_template "$template_choice")
                                        if [ -n "$custom_scripts" ]; then
                                            log_info "Applied script template: $template_choice"
                                        fi
                                    fi
                                    ;;
                            esac
                        fi
                    fi
                fi
        fi # This 'fi' closes the "if [ "$ci_config_type" = "default" ]; then" block
    fi # This 'fi' closes the "if [ "$use_cloudinit" = "yes" ]; then" (after config type choice)

    # --- Step 7: Tagging/Categorization ---
    tags=$(whiptail --title "Tags" --inputbox "Enter tags (comma-separated):" 10 60 "" 3>&1 1>&2 2>&3)
    tags_result=$?
    if [ $tags_result -ne 0 ]; then return 0; fi

    # --- Step 8: Validate Configuration ---
    if ! validate_template_config; then
        log_error "Template configuration validation failed"
        return 1
    fi

    # --- Step 9: Confirm and Create ---
    summary="Template: $template_name\nDistro: $distro $version\nCPU: $cpu\nRAM: $ram MB\nDisk: $storage GB\nCloud-Init: $use_cloudinit\nTags: $tags"
    if [ "$use_cloudinit" = "yes" ]; then
        summary+="\nCloud-Init Method: $ci_config_type"
        if [ "$ci_config_type" = "default" ]; then
            summary+="\nUser: $ci_user\nSSH Key: ${ci_sshkey:0:30}..."
            if [ "$ci_password_enabled" = "yes" ]; then
                summary+="\nPassword: Enabled"
            else
                summary+="\nPassword: Disabled"
            fi
            summary+="\nNetwork: $ci_network"
            if [ -n "$install_packages" ]; then
                summary+="\nPackages: $install_packages"
            fi
            if [ -n "$custom_scripts" ]; then
                summary+="\nCustom Scripts: Configured"
            else
                summary+="\nCustom Scripts: None"
            fi
        elif [ "$ci_config_type" = "custom_file" ]; then
            summary+="\nCustom File: $custom_ci_user_data_path"
        elif [ "$ci_config_type" = "custom_paste" ]; then
            summary+="\nCustom Data: Pasted (first 30 chars: ${custom_ci_user_data_content:0:30}...)"
        fi
    fi

    if ! whiptail --title "Confirm Template Creation" --yesno "$summary\n\nProceed?" 20 70; then
        log_info "User cancelled at confirmation."
        return 0
    fi

    # Exit here if in test mode
    if [ -n "$TEST_MODE" ]; then
        log_info "Test mode - exiting before VM creation."
        return 0
    fi

    # --- Step 8: Proxmox Automation ---
    # Find next available VMID
    storage_pools=$(pvesh get /storage --output-format=json | jq -r '.[].storage')
    default_storage="local-lvm"  # Use a safe default

    # Check if local-lvm exists, otherwise try to find another storage
    if ! echo "$storage_pools" | grep -q "^local-lvm$"; then
        # Try to find another storage that supports disk images
        for pool in $storage_pools; do
            if pvesh get /storage/"$pool" --output-format=json | jq -r '.content' | grep -q "images"; then
                default_storage="$pool"
                break
            fi
        done
    fi

    # Get next available VMID
    vmid=$(pvesh get /cluster/nextid)
    log_info "Using VMID: $vmid"

    # Download image
    iso_dir="/var/lib/vz/template/iso"
    iso_name="${distro}-${version}-$(date +%Y%m%d).qcow2"
    iso_path="$iso_dir/$iso_name"

    # Create ISO directory if it doesn't exist
    mkdir -p "$iso_dir"

    # Get URL template and replace version placeholder
    url_template=$(get_distro_url_template "$distro")
    if [ -z "$url_template" ]; then
        log_error "Failed to get download URL template for $distro"
        whiptail --title "Error" --msgbox "Failed to get download URL template for $distro." 10 60
        return 1
    fi

    # Replace version placeholder in URL
    download_url="${url_template//%version%/$version}"
    log_info "Download URL: $download_url"

    if [ ! -f "$iso_path" ]; then
        log_info "Downloading image for $distro $version..."
        whiptail --title "Downloading" --infobox "Downloading $distro $version image...\nThis may take a few minutes." 10 60

        # Download the image
        if ! curl -L -o "$iso_path" "$download_url"; then
            log_error "Failed to download image from $download_url"
            whiptail --title "Error" --msgbox "Failed to download image. Check network connection and try again." 10 60
            rm -f "$iso_path"  # Clean up partial download
            return 1
        fi
    fi

    # Create VM
    log_info "Creating VM $vmid ($template_name)..."
    whiptail --title "Creating VM" --infobox "Creating VM $vmid ($template_name)..." 10 60

    if ! qm create "$vmid" --name "$template_name" --memory "$ram" --cores "$cpu" --net0 "virtio,bridge=vmbr0"; then
        log_error "Failed to create VM $vmid"
        whiptail --title "Error" --msgbox "Failed to create VM $vmid. Check logs for details." 10 60
        return 1
    fi

    # Set additional VM parameters
    qm set "$vmid" --scsihw virtio-scsi-pci
    qm set "$vmid" --ostype l26

    # Import disk (cloud image)
    log_info "Importing disk image..."
    if ! qm importdisk "$vmid" "$iso_path" "$default_storage"; then
        log_error "Failed to import disk from $iso_path to $default_storage"
        whiptail --title "Error" --msgbox "Failed to import disk. Check storage configuration." 10 60
        return 1
    fi

    # Attach disk
    log_info "Attaching disk to VM..."
    qm set "$vmid" --scsi0 "$default_storage:vm-$vmid-disk-0"
    qm set "$vmid" --boot order=scsi0

    # Resize disk if needed (default size of cloud images is often small)
    qm resize "$vmid" scsi0 "${storage}G"

    # Add cloud-init drive if selected
    if [ "$use_cloudinit" = "yes" ]; then
        log_info "Configuring cloud-init for VM $vmid..."
        # This adds the cloud-init drive itself. $default_storage should be suitable for this.
        # Ensure $default_storage is a storage that can accept 'cloudinit' content type or PVE can handle it.
        qm set "$vmid" --ide2 "$default_storage:cloudinit"

        if [ "$ci_config_type" = "default" ]; then
            log_info "Applying default (guided) cloud-init configuration..."
            # Only set ciuser if it's not empty (it's gathered in the default path)
            if [ -n "$ci_user" ]; then
                qm set "$vmid" --ciuser "$ci_user"
            fi

            if [ -n "$ci_sshkey" ]; then
                # Using a temporary file for SSH keys is robust
                local TMP_SSH_KEY_FILE
                TMP_SSH_KEY_FILE=$(mktemp "/tmp/sshkey-$vmid-XXXXXX.pub")
                # Ensure content is written correctly, especially if $ci_sshkey might have special chars
                printf '%s' "$ci_sshkey" > "$TMP_SSH_KEY_FILE"
                qm set "$vmid" --sshkeys "$TMP_SSH_KEY_FILE"
                rm -f "$TMP_SSH_KEY_FILE"
                log_info "SSH key configured for user $ci_user"
            fi

            if [ "$ci_password_enabled" = "yes" ] && [ -n "$ci_password" ]; then
                qm set "$vmid" --cipassword "$ci_password"
                log_info "Password authentication configured for user $ci_user"
            fi

            # $ci_network will be "dhcp" or "ip=...,gw=...,nameserver=..."
            if [ "$ci_network" = "dhcp" ]; then
                qm set "$vmid" --ipconfig0 "ip=dhcp"
            elif [ -n "$ci_network" ]; then # Static config
                qm set "$vmid" --ipconfig0 "$ci_network"
            fi

            # Generate and apply CLOUD_INIT_FILE for packages and custom scripts
            # This part creates a #cloud-config file with packages and runcmd sections
            # Only run this if there are packages to install or custom scripts to run
            # (The qemu-guest-agent is now included in this logic)
            if [ -n "$install_packages" ] || [ -n "$custom_scripts" ]; then
                log_info "Generating cloud-init payload for packages and/or custom scripts..."
                local TMP_CLOUD_INIT_PAYLOAD_FILE
                TMP_CLOUD_INIT_PAYLOAD_FILE=$(mktemp "/tmp/ci-payload-$vmid-XXXXXX.yaml")
                cat > "$TMP_CLOUD_INIT_PAYLOAD_FILE" << EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
EOF
                if [ -n "$install_packages" ]; then
                    for package_name_iter in $install_packages; do # Renamed loop variable
                        echo "  - $package_name_iter" >> "$TMP_CLOUD_INIT_PAYLOAD_FILE"
                    done
                fi
                # Always include qemu-guest-agent if using this custom payload
                echo "  - qemu-guest-agent" >> "$TMP_CLOUD_INIT_PAYLOAD_FILE"

                cat >> "$TMP_CLOUD_INIT_PAYLOAD_FILE" << EOF
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
                if [ -n "$custom_scripts" ]; then
                    echo "  # Custom scripts" >> "$TMP_CLOUD_INIT_PAYLOAD_FILE"
                    # Properly indent multi-line scripts for YAML runcmd
                    # Each command or script block should be a list item.
                    # If custom_scripts contains multiple lines intended as one script,
                    # it should be formatted as a YAML block scalar.
                    # For simplicity here, assuming custom_scripts are line-separated commands.
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                             # Escape double quotes in the line for safety
                            echo "  - \"$(echo "$line" | sed 's/"/\\"/g')\"" >> "$TMP_CLOUD_INIT_PAYLOAD_FILE"
                        fi
                    done <<< "$custom_scripts"
                fi

                local default_ci_snippet_filename="ci-std-payload-$vmid-$(date +%s).yaml"
                local SNIPPET_STORAGE_FOR_DEFAULT_CI="local"
                log_info "Uploading default cloud-init payload to $SNIPPET_STORAGE_FOR_DEFAULT_CI snippets as $default_ci_snippet_filename"
                if pvesm upload "$SNIPPET_STORAGE_FOR_DEFAULT_CI" "$TMP_CLOUD_INIT_PAYLOAD_FILE" --filename "$default_ci_snippet_filename" --content snippets; then
                     qm set "$vmid" --cicustom "user=$SNIPPET_STORAGE_FOR_DEFAULT_CI:snippets/$default_ci_snippet_filename"
                     # This snippet is specific to this VM's default setup, not typically marked for deletion unless VM is destroyed.
                else
                     log_error "Failed to upload default cloud-init payload to $SNIPPET_STORAGE_FOR_DEFAULT_CI snippets."
                     whiptail --title "Error" --msgbox "Failed to upload default cloud-init payload. Check '$SNIPPET_STORAGE_FOR_DEFAULT_CI' storage. VM may lack packages/scripts." 10 78
                fi
                rm -f "$TMP_CLOUD_INIT_PAYLOAD_FILE"
            else
                # If no packages and no custom_scripts, still ensure qemu-guest-agent is installed and started
                log_info "Generating cloud-init payload for QEMU guest agent only..."
                local TMP_QEMU_AGENT_ONLY_FILE
                TMP_QEMU_AGENT_ONLY_FILE=$(mktemp "/tmp/ci-qemu-agent-$vmid-XXXXXX.yaml")
                cat > "$TMP_QEMU_AGENT_ONLY_FILE" << EOF
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
                local qemu_agent_only_snippet_filename="ci-qga-only-$vmid-$(date +%s).yaml"
                local SNIPPET_STORAGE_FOR_DEFAULT_CI="local"
                log_info "Uploading QEMU agent-only cloud-init payload to $SNIPPET_STORAGE_FOR_DEFAULT_CI snippets as $qemu_agent_only_snippet_filename"
                if pvesm upload "$SNIPPET_STORAGE_FOR_DEFAULT_CI" "$TMP_QEMU_AGENT_ONLY_FILE" --filename "$qemu_agent_only_snippet_filename" --content snippets; then
                     qm set "$vmid" --cicustom "user=$SNIPPET_STORAGE_FOR_DEFAULT_CI:snippets/$qemu_agent_only_snippet_filename"
                else
                     log_error "Failed to upload QEMU agent-only cloud-init payload to $SNIPPET_STORAGE_FOR_DEFAULT_CI snippets."
                fi
                rm -f "$TMP_QEMU_AGENT_ONLY_FILE"
            fi

        elif [ "$ci_config_type" = "custom_file" ]; then
            log_info "Applying custom user-data from file: $custom_ci_user_data_path"
            if [ -z "$custom_ci_user_data_path" ]; then
                log_error "Custom user-data file path is empty. Skipping cicustom."
                whiptail --title "Error" --msgbox "Custom user-data file path was not set. Cloud-init custom configuration will be skipped." 8 78
            else
                # Validate format: storage:snippets/file.yaml
                if [[ "$custom_ci_user_data_path" != *":"* || "$custom_ci_user_data_path" != *"snippets/"* ]]; then
                    log_error "Invalid custom_ci_user_data_path format: $custom_ci_user_data_path. Expected 'storage:snippets/filename.yaml'."
                    whiptail --title "Error" --msgbox "Invalid custom user-data path format. Expected 'storage:snippets/filename.yaml'." 8 78
                else
                    qm set "$vmid" --cicustom "user=$custom_ci_user_data_path"
                    log_info "Set cicustom to user=$custom_ci_user_data_path"
                fi
            fi

        elif [ "$ci_config_type" = "custom_paste" ]; then
            log_info "Applying custom user-data from pasted content..."
            if [ -z "$custom_ci_user_data_content" ]; then
                log_warn "Pasted custom user-data is empty. Skipping cicustom."
            else
                local TMP_CUSTOM_PASTE_UPLOAD_FILE
                TMP_CUSTOM_PASTE_UPLOAD_FILE=$(mktemp "/tmp/custom-ci-paste-vmid${vmid}-XXXXXX.yaml")
                printf '%s' "$custom_ci_user_data_content" > "$TMP_CUSTOM_PASTE_UPLOAD_FILE"

                local pasted_ci_snippet_filename="custom-ci-paste-vmid${vmid}-$(date +%s).yaml"
                # Default storage for pasted snippets. Consider making this configurable or detecting a suitable one.
                local SNIPPET_STORAGE_FOR_PASTED_CI="local"
                # Host path for 'local' storage type snippets. This is where the file will reside for Proxmox.
                local SNIPPET_HOST_PATH_FOR_PASTED_CI="/var/lib/vz/snippets"

                # Ensure the target directory for 'local' snippets exists.
                if [ "$SNIPPET_STORAGE_FOR_PASTED_CI" = "local" ] && [ ! -d "$SNIPPET_HOST_PATH_FOR_PASTED_CI" ]; then
                    log_info "Creating snippet directory for 'local' storage: $SNIPPET_HOST_PATH_FOR_PASTED_CI"
                    # This might need sudo if script is not root, but create_template is usually root.
                    mkdir -p "$SNIPPET_HOST_PATH_FOR_PASTED_CI"
                fi

                log_info "Uploading pasted custom user-data to $SNIPPET_STORAGE_FOR_PASTED_CI snippets as $pasted_ci_snippet_filename"
                if pvesm upload "$SNIPPET_STORAGE_FOR_PASTED_CI" "$TMP_CUSTOM_PASTE_UPLOAD_FILE" --filename "$pasted_ci_snippet_filename" --content snippets; then
                    qm set "$vmid" --cicustom "user=$SNIPPET_STORAGE_FOR_PASTED_CI:snippets/$pasted_ci_snippet_filename"
                    log_info "Set cicustom to user=$SNIPPET_STORAGE_FOR_PASTED_CI:snippets/$pasted_ci_snippet_filename"
                    # Store the full path on the Proxmox host for later deletion if it's on 'local' storage
                    if [ "$SNIPPET_STORAGE_FOR_PASTED_CI" = "local" ]; then
                        ephemeral_snippet_path_to_delete="$SNIPPET_HOST_PATH_FOR_PASTED_CI/$pasted_ci_snippet_filename"
                    fi
                else
                    log_error "Failed to upload pasted custom user-data to $SNIPPET_STORAGE_FOR_PASTED_CI snippets."
                    whiptail --title "Error" --msgbox "Failed to upload pasted custom user-data to $SNIPPET_STORAGE_FOR_PASTED_CI. Check storage configuration. Cloud-init may not be correctly configured." 12 78
                fi
                rm -f "$TMP_CUSTOM_PASTE_UPLOAD_FILE"
            fi
        fi
    fi

    # Add tags if provided
    if [ -n "$tags" ]; then
        qm set "$vmid" --tags "$tags"
    fi

    # Set VM description with creation info
    creation_info="Created: $(date '+%Y-%m-%d %H:%M:%S')\nDistribution: $distro $version\nCloud-Init: $use_cloudinit"
    qm set "$vmid" --description "$creation_info"

    # Convert to template
    log_info "Converting VM $vmid to template..."
    qm template "$vmid"

    log_info "Template $template_name ($vmid) created successfully."
    whiptail --title "Success" --msgbox "Template $template_name ($vmid) created successfully!" 10 60

    # Clean up ephemeral snippet if one was created for pasted custom CI data
    if [ -n "$ephemeral_snippet_path_to_delete" ] && [ -f "$ephemeral_snippet_path_to_delete" ]; then
        log_info "Cleaning up temporary snippet: $ephemeral_snippet_path_to_delete"
        if rm -f "$ephemeral_snippet_path_to_delete"; then
            log_info "Successfully deleted temporary snippet."
        else
            log_warn "Failed to delete temporary snippet: $ephemeral_snippet_path_to_delete. Manual cleanup may be required."
        fi
        ephemeral_snippet_path_to_delete="" # Clear the variable
    fi
    return 0
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Proxmox Template Creator" --menu "Select an option:" 20 70 8 \
            "1" "Create new template" \
            "2" "List all templates" \
            "3" "Manage existing templates" \
            "4" "Validate template" \
            "5" "Test template" \
            "6" "Template configuration management" \
            "7" "Help and documentation" \
            "8" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                create_template
                ;;
            2)
                list_templates
                ;;
            3)
                manage_templates
                ;;
            4)
                validate_template
                ;;
            5)
                test_template
                ;;
            6)
                manage_template_config
                ;;
            7)
                show_help
                ;;
            8|"")
                log_info "Exiting template creator"
                exit 0
                ;;
        esac
    done
}

# Check if running in direct create mode or as CLI arguments
if [ "$1" = "--create" ] || [ -n "$CREATE_MODE" ]; then
    # Run pre-checks and go directly to template creation
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    create_template
    exit $?
elif [ $# -eq 0 ]; then
    # No arguments provided, show main menu
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    main_menu
else
    # Arguments were provided and handled at the beginning of the script
    # This handles --list-distros, --list-versions, --test, etc.
    log_info "CLI arguments were processed at script start"
fi
