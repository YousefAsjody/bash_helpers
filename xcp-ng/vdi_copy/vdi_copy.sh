#!/bin/bash
# Usage: ./vdi_copy.sh <VM_NAME> <TARGET_SR_UUID>

set -e

VM_NAME="$1"
TARGET_SR="$2"

if [[ -z "$VM_NAME" || -z "$TARGET_SR" ]]; then
    echo "Usage: $0 <VM_NAME> <TARGET_SR_UUID>"
    exit 1
fi

echo "Migrating VM '$VM_NAME' to SR '$TARGET_SR'..."

# Get VM UUID
VM_UUID=$(xe vm-list name-label="$VM_NAME" --minimal)
if [[ -z "$VM_UUID" ]]; then
    echo "Error: VM '$VM_NAME' not found!"
    exit 1
fi
echo "VM UUID: $VM_UUID"

# Shutdown VM
echo "Shutting down VM..."
xe vm-shutdown uuid=$VM_UUID --force || true

# Wait until VM stops
echo "Waiting for VM to stop..."
while xe vm-list uuid=$VM_UUID power-state=running --minimal | grep -q .; do
    sleep 5
done
echo "VM is stopped."

# Get all VBDs (disks)
VBD_LIST=$(xe vbd-list vm-uuid=$VM_UUID type=Disk --minimal | tr ',' '\n')

for VBD in $VBD_LIST; do
    echo "Processing VBD: $VBD"

    # Get VDI info
    VDI=$(xe vbd-param-get uuid=$VBD param-name=vdi-uuid)
    VDI_NAME=$(xe vdi-param-get uuid=$VDI param-name=name-label)
    echo "Found VDI '$VDI_NAME' ($VDI)"

    # Copy VDI to target SR
    NEW_VDI=$(xe vdi-copy uuid=$VDI sr-uuid=$TARGET_SR)
    echo "Copied VDI to new VDI UUID: $NEW_VDI"

    # Rename old VDI
    xe vdi-param-set uuid=$VDI name-label="$VDI_NAME [old]"
    echo "Renamed old VDI to '$VDI_NAME [old]'"

    # Detach old VBD
    xe vbd-unplug uuid=$VBD || true
    echo "Detached old VBD"

    # Destroy old VBD
    xe vbd-destroy uuid=$VBD || true
    echo "Destroyed old VBD"

    # Attach new VDI
    NEW_VBD=$(xe vbd-create vm-uuid=$VM_UUID vdi-uuid=$NEW_VDI device=autodetect bootable=true mode=RW type=Disk)
    echo "Attached (configured) new VDI ($NEW_VDI) to VM as VBD: $NEW_VBD (will plug on boot)"

done

# Start VM
echo "Starting VM..."
xe vm-start uuid=$VM_UUID

echo "Migration completed successfully!"
