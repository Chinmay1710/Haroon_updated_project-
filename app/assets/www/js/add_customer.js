/**
 * add_customer.js - Data binding for Add Customer screen with duplicate check
 */

let existingCustomersList = [];

function cleanMobile(num) {
  if (!num) return '';
  return num.replace(/\D/g, '').slice(-10);
}

document.addEventListener("DOMContentLoaded", async function() {
  try {
    existingCustomersList = await window.API.request('get_customers');
  } catch(e) {
    existingCustomersList = [];
  }

  const mobileEl = document.getElementById('customerMobile');
  const warnBox = document.getElementById('duplicate-warning-box');
  const warnText = document.getElementById('duplicate-warning-text');
  const btnSave = document.getElementById('btn-save-customer');
  const btnSaveOrder = document.getElementById('btn-save-add-measurements');

  if (mobileEl) {
    mobileEl.addEventListener('input', function() {
      const clean = cleanMobile(this.value);
      if (clean.length === 10) {
        const match = existingCustomersList.find(c => cleanMobile(c.mobile) === clean);
        if (match) {
          if (warnText) warnText.textContent = `Yeh number pehle se "${match.name}" ke naam se darj hai! Duplicate allow nahi hai.`;
          if (warnBox) warnBox.classList.remove('hidden');
          if (btnSave) btnSave.disabled = true;
          if (btnSaveOrder) btnSaveOrder.disabled = true;
          window.API.toast(`⚠️ Yeh number pehle se "${match.name}" ke paas hai!`, "warning");
          return;
        }
      }
      if (warnBox) warnBox.classList.add('hidden');
      if (btnSave) btnSave.disabled = false;
      if (btnSaveOrder) btnSaveOrder.disabled = false;
    });
  }

  if (window.API && window.API.attachMic) {
    window.API.attachMic('customerName');
    window.API.attachMic('customerAddress');
    window.API.attachMic('customerNotes');
  }
});

async function saveCustomer(targetPage) {
  const nameEl = document.getElementById('customerName');
  const mobileEl = document.getElementById('customerMobile');
  const addressEl = document.getElementById('customerAddress');
  const notesEl = document.getElementById('customerNotes');

  if (!nameEl || !mobileEl) return;

  const rawMobile = mobileEl.value.trim();
  const cleanNum = cleanMobile(rawMobile);

  const payload = {
    name: nameEl.value.trim(),
    mobile: cleanNum.length === 10 ? `+91 ${cleanNum}` : rawMobile,
    address: addressEl ? addressEl.value.trim() : "",
    notes: notesEl ? notesEl.value.trim() : ""
  };

  if (!payload.name) {
    window.API.toast("Grahak ka naam zaroori hai", "error");
    return;
  }

  if (cleanNum.length !== 10) {
    window.API.toast("Mobile number 10 digits ka hona chahiye (e.g. 9876543210)", "error");
    return;
  }

  // Duplicate customer check
  const match = existingCustomersList.find(c => cleanMobile(c.mobile) === cleanNum);
  if (match) {
    window.API.toast(`⚠️ Yeh number pehle se "${match.name}" ke paas hai! Duplicate customer allow nahi hai.`, "error");
    return;
  }

  try {
    const response = await window.API.request('create_customer', payload);
    window.API.toast("Grahak save ho gaya!", "success");

    if (targetPage === 'new_order' && response.id) {
      window.API.request('navigate_to', { page: 'new_order', customer_id: response.id });
    } else {
      window.API.navigate(targetPage);
    }
  } catch (e) {
    window.API.toast(e.toString(), "error");
  }
}
