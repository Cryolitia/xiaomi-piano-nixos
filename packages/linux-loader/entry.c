// SPDX-License-Identifier: BSD-2-Clause-Patent
// The same entry/exit lifecycle as EDK2's UefiApplicationEntryPoint libraries.
#include <Uefi.h>
#include <Guid/EventGroup.h>
#include <Library/BaseLib.h>
#include <Library/UefiBootServicesTableLib.h>

EFI_SYSTEM_TABLE *gST;
EFI_BOOT_SERVICES *gBS;
EFI_GUID gEfiEventExitBootServicesGuid = EFI_EVENT_GROUP_EXIT_BOOT_SERVICES;

EFI_STATUS EFIAPI PianoLinuxBootEntry(EFI_HANDLE Image, EFI_SYSTEM_TABLE *Table);
EFI_STATUS EFIAPI PianoProductPumpLibDestructor(EFI_HANDLE Image,
                                               EFI_SYSTEM_TABLE *Table);

VOID EFIAPI CpuDeadLoop(VOID) {
  __asm__ volatile("msr daifset, #15" ::: "memory");
  for (;;) {
    __asm__ volatile("wfe" ::: "memory");
  }
}

EFI_STATUS EFIAPI PianoEfiEntry(EFI_HANDLE Image, EFI_SYSTEM_TABLE *Table) {
  if (Image == NULL || Table == NULL || Table->BootServices == NULL ||
      Table->Hdr.Signature != EFI_SYSTEM_TABLE_SIGNATURE ||
      Table->BootServices->Hdr.Signature != EFI_BOOT_SERVICES_SIGNATURE)
    return EFI_INVALID_PARAMETER;
  gST = Table;
  gBS = Table->BootServices;
  EFI_STATUS Status = PianoLinuxBootEntry(Image, Table);
  EFI_STATUS Cleanup = PianoProductPumpLibDestructor(Image, Table);
  if (Cleanup != EFI_SUCCESS)
    CpuDeadLoop();
  return Status;
}
