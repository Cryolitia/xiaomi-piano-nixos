{ pianoPackages, ... }:

let
  runtime = "${pianoPackages.bsp}/libexec/piano";
in
{
  # Keep the local display as /dev/console while also forwarding printk to ACM.
  # This is a normal USB console; it starts after the host enumerates the gadget.
  boot.kernelParams = [
    "console=ttyGS0"
    "console=tty0"
  ];

  environment.etc."piano/linux-debug.conf".text = ''
    usb=acm-ncm
  '';

  # The pinned gadget script owns 10.42.0.2/24. Its host peer uses 10.42.0.1;
  # NetworkManager must not replace this link with an automatic wired profile.
  networking.networkmanager.unmanaged = [ "interface-name:usb0" ];

  # Preserve the board's Type-C orientation and device-role readiness checks.
  services.udev.extraRules = builtins.readFile (
    pianoPackages.bsp.src + "/linux/bsp/common/etc/udev/rules.d/79-piano-usb.rules"
  );

  # Keep the serial channel for logs rather than an additional login prompt.
  systemd.services."serial-getty@ttyGS0".enable = false;

  systemd.services.piano-usb = {
    description = "Piano USB diagnostic connection";
    wants = [ "piano-adsp.service" ];
    bindsTo = [ "sys-subsystem-typec-devices-port0.device" ];
    after = [
      "piano-adsp.service"
      "sys-subsystem-typec-devices-port0.device"
    ];

    # Udev starts this only when the USB-C connection is ready. A missing cable
    # therefore does not enqueue a device job in the normal boot transaction.
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${runtime}/usb-network";
      ExecStop = "${runtime}/usb-network stop";
      TimeoutStartSec = 130;
    };
  };

}
