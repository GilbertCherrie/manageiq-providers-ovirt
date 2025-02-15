class ManageIQ::Providers::Redhat::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include_concern 'Operations'
  include_concern 'RemoteConsole'
  include_concern 'Reconfigure'
  include_concern 'ManageIQ::Providers::Redhat::InfraManager::VmOrTemplateShared'

  supports :migrate do
    if blank? || orphaned? || archived?
      unsupported_reason_add(:migrate, "Migrate operation in not supported.")
    elsif !ext_management_system.supports?(:migrate)
      unsupported_reason_add(:migrate, 'RHV API version does not support migrate')
    end
  end

  supports :reconfigure_disks do
    if storage.blank?
      unsupported_reason_add(:reconfigure_disks, _('storage is missing'))
    elsif ext_management_system.blank?
      unsupported_reason_add(:reconfigure_disks, _('The virtual machine is not associated with a provider'))
    elsif !ext_management_system.supports?(:reconfigure_disks)
      unsupported_reason_add(:reconfigure_disks, _('The provider does not support reconfigure disks'))
    end
  end

  supports_not :reset
  supports :publish do
    if blank? || orphaned? || archived?
      unsupported_reason_add(:publish, _('Publish operation in not supported'))
    elsif ext_management_system.blank?
      unsupported_reason_add(:publish, _('The virtual machine is not associated with a provider'))
    elsif !ext_management_system.supports?(:publish)
      unsupported_reason_add(:publish, _('This feature is not supported by the api version of the provider'))
    elsif power_state != "off"
      unsupported_reason_add(:publish, _('The virtual machine must be down'))
    end
  end

  supports :reconfigure_network_adapters

  # supports :reconfigure_disksize
  supports :reconfigure_disksize do
    unsupported_reason_add(:reconfigure_disksize, 'Cannot resize disks of a VM with snapshots') if snapshots.count > 1
  end

  POWER_STATES = {
    'up'          => 'on',
    'powering_up' => 'on',
    'down'        => 'off',
    'suspended'   => 'suspended',
  }.freeze

  def provider_object(connection = nil)
    ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4.new(:ems => ext_management_system).get_vm_proxy(self, connection)
  end

  def scan_via_ems?
    true
  end

  def parent_cluster
    rp = parent_resource_pool
    rp && rp.detect_ancestor(:of_type => "EmsCluster").first
  end
  alias owning_cluster parent_cluster
  alias ems_cluster parent_cluster

  def disconnect_storage(_s = nil)
    return unless active?

    vm_storages = ([storage] + storages).compact.uniq
    return if vm_storages.empty?

    vm_disks = collect_disks
    storage = vm_disks.blank? ? nil : vm_storages.select { |store| !vm_disks.include?(store.ems_ref) }

    super(storage)
  end

  def collect_disks
    return [] if hardware.nil?
    disks = hardware.disks.map do |disk|
      unless disk.storage.nil?
        "#{disk.storage.ems_ref}/disks/#{disk.filename}"
      end
    end
    ext_management_system.ovirt_services.collect_disks_by_hrefs(disks.compact)
  end

  def exists_on_provider?
    return false unless ext_management_system
    ext_management_system.ovirt_services.vm_exists_on_provider?(self)
  end

  def params_for_create_snapshot
    {
      :fields => [
        {
          :component  => 'textarea',
          :name       => 'description',
          :id         => 'description',
          :label      => _('Description'),
          :isRequired => true,
          :validate   => [{:type => 'required'}],
        },
        {
          :component  => 'switch',
          :name       => 'memory',
          :id         => 'memory',
          :label      => _('Snapshot VM memory'),
          :onText     => _('Yes'),
          :offText    => _('No'),
          :isDisabled => current_state != 'on',
          :helperText => _('Snapshotting the memory is only available if the VM is powered on.'),
        },
      ],
    }
  end

  #
  # UI Button Validation Methods
  #

  def has_required_host?
    true
  end

  def self.calculate_power_state(raw_power_state)
    POWER_STATES[raw_power_state] || super
  end

  def self.display_name(number = 1)
    n_('Virtual Machine (Red Hat)', 'Virtual Machines (Red Hat)', number)
  end
end
