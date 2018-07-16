# Cody Shearer - cjshearer@live.com - 07/10/2018
# Based on docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-volumes.html#windows-list-disks
require 'win32ole'
require 'open-uri'
require 'json'
out = {}
wmi = WIN32OLE.connect("Winmgmts:\\\\")
disk_drives = wmi.ExecQuery("select * from win32_DiskDrive")
for disk_drive in disk_drives
  disk_partitions = wmi.ExecQuery("ASSOCIATORS OF
                                  {Win32_DiskDrive.DeviceID='#{disk_drive.DeviceId}'}
                                  WHERE AssocClass=Win32_DiskDriveToDiskPartition")
  for disk_partition in disk_partitions
    logical_disks = wmi.ExecQuery("ASSOCIATORS OF
                                 {Win32_DiskPartition.DeviceID='#{disk_partition.DeviceId}'}
                                 WHERE AssocClass=Win32_LogicalDiskToPartition")
    for logical_disk in logical_disks
      out.merge!(logical_disk.Name.chop =>
                     {
                         'name'            =>logical_disk.Name.chop,
                         'root'            =>logical_disk.Name+'\\',
                         'description'     =>logical_disk.VolumeName,
                         'display_root'    =>logical_disk.ProviderName,
                         'used_bytes'      =>Integer(logical_disk.Size)-Integer(logical_disk.FreeSpace),
                         'free_bytes'      =>Integer(logical_disk.FreeSpace),
                         'drive_type'      =>disk_drive.MediaType[0,disk_drive.MediaType.index(' ')],
                         'pnp_device_id'   =>disk_drive.PNPDeviceId,
                         'scsi_target_id'  =>disk_drive.SCSITargetId,
                         'scsi_port'       =>disk_drive.SCSIPort
                     }
      )
    end
  end
end

def convert_target_id_to_device_name(target_id)
  id = Integer(target_id)
  if id == 0
    return '/dev/sda1'
  end
  ret = 'xvd'
  if id > 25
    ret += (96+(id/26)).chr
  end
  ret += (97+(id%26)).chr
  return ret
end

def get_ec2_instance_metadata(path)
  return open("http://169.254.169.254/latest/#{path}").read
end

# Find block device name
for drive_info in out
  # If non-NVME...
  if drive_info[1]['pnp_device_id'].include? 'PROD_PVDISK'
    # Use SCSI Target Id to generate block device
    drive_info[1].merge!('block_device' => convert_target_id_to_device_name(drive_info[1]['scsi_target_id']))

  # If NVME...
  elsif drive_info[1]['pnp_device_id'].include? 'PROD_AMAZON_EC2_NVME'
    # Use SCSI Port to find block device from metadata
    drive_info[1].merge!('block_device' => get_ec2_instance_metadata("meta-data/block-device-mapping/ephemeral#{drive_info[1]['scsi_port']}"))

  # Is non-EC2 volume
  else
    drive_info[1].merge!('block_device' => nil)
  end
end
puts(JSON.pretty_generate(out))