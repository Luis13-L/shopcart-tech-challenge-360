import Swal from "sweetalert2";

interface ConfirmOptions {
  title: string;
  text: string;
  confirmText?: string;
  danger?: boolean;
}

export async function confirmAction({
  title,
  text,
  confirmText = "Sí, confirmar",
  danger = false
}: ConfirmOptions): Promise<boolean> {

  const result = await Swal.fire({
    title,
    text,
    icon: danger ? "warning" : "question",
    showCancelButton: true,
    confirmButtonText: confirmText,
    cancelButtonText: "Cancelar",
    confirmButtonColor: danger
      ? "#b43a50"
      : "#7162ed",
    cancelButtonColor: "#85899b",
    reverseButtons: true,
    focusCancel: true
  });

  return result.isConfirmed;
}

export async function showSuccess(
  title: string,
  text: string
): Promise<void> {
  await Swal.fire({
    icon: "success",
    title,
    text,
    confirmButtonText: "Aceptar",
    confirmButtonColor: "#7162ed"
  });
}

export async function showError(
  title: string,
  text: string
): Promise<void> {
  await Swal.fire({
    icon: "error",
    title,
    text,
    confirmButtonText: "Entendido",
    confirmButtonColor: "#7162ed"
  });
}
