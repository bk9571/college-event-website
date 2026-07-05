// TechnoVista - shared site interactivity

document.addEventListener('DOMContentLoaded', () => {
  initNavToggle();
  initRegistrationForm();
});

function initNavToggle() {
  const toggle = document.getElementById('navToggle');
  const links = document.getElementById('navLinks');
  if (!toggle || !links) return;

  toggle.addEventListener('click', () => {
    const isOpen = links.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(isOpen));
    toggle.classList.toggle('active', isOpen);
  });

  links.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      links.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
      toggle.classList.remove('active');
    });
  });
}

function initRegistrationForm() {
  const form = document.getElementById('registrationForm');
  if (!form) return;

  const successMsg = document.getElementById('formSuccessMsg');

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    clearErrors(form);

    let isValid = true;

    isValid = validateRequired(form, 'fullName', 'Full name is required.') && isValid;
    isValid = validateEmail(form) && isValid;
    isValid = validatePhone(form) && isValid;
    isValid = validateRequired(form, 'college', 'College name is required.') && isValid;
    isValid = validateRequired(form, 'track', 'Please select a track.') && isValid;

    if (isValid) {
      form.reset();
      if (successMsg) {
        successMsg.hidden = false;
      }
    } else if (successMsg) {
      successMsg.hidden = true;
    }
  });
}

function validateRequired(form, fieldName, message) {
  const field = form.elements[fieldName];
  if (!field.value.trim()) {
    showError(fieldName, message);
    return false;
  }
  return true;
}

function validateEmail(form) {
  const field = form.elements['email'];
  const value = field.value.trim();
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  if (!value) {
    showError('email', 'Email address is required.');
    return false;
  }
  if (!emailPattern.test(value)) {
    showError('email', 'Please enter a valid email address.');
    return false;
  }
  return true;
}

function validatePhone(form) {
  const field = form.elements['phone'];
  const value = field.value.trim();
  const phonePattern = /^[0-9]{10}$/;

  if (!value) {
    showError('phone', 'Phone number is required.');
    return false;
  }
  if (!phonePattern.test(value)) {
    showError('phone', 'Enter a valid 10-digit phone number.');
    return false;
  }
  return true;
}

function showError(fieldName, message) {
  const field = document.getElementById(fieldName);
  const errorEl = document.querySelector(`[data-error-for="${fieldName}"]`);
  if (field) field.classList.add('input-error');
  if (errorEl) errorEl.textContent = message;
}

function clearErrors(form) {
  form.querySelectorAll('.input-error').forEach((el) => el.classList.remove('input-error'));
  form.querySelectorAll('.error-msg').forEach((el) => (el.textContent = ''));
}
