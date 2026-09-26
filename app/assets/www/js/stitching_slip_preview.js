/**
 * stitching_slip_preview.js - Render dynamic stitching slip data before printing (58mm POS format)
 */

document.addEventListener("DOMContentLoaded", function() {
 function init() {
 if (!window.pyBridge) {
 setTimeout(init, 100);
 return;
 }
 
 let navParamsStr = sessionStorage.getItem("nav_params");
 let navParams = navParamsStr ? JSON.parse(navParamsStr) : null;
 
 if (!navParams || !navParams.order_id) {
 window.API.toast("No order ID provided.", "error");
 document.getElementById('ss-order-number').textContent = "Error";
 return;
 }
 
 loadSlipData(navParams.order_id);
 }
 init();
});

async function loadSlipData(orderId) {
 try {
 const o = await window.API.request('get_order_details', {id: orderId});
 const container = document.getElementById('slips-container');
 container.innerHTML = '';
 
 if (!o.items || o.items.length === 0) {
 container.innerHTML = '<div style="text-align:center; padding: 20px;">No items in order</div>';
 return;
 }
 
 // Need shop name from global if possible, or fallback
 let shopName = "Haroon Tailor";
 try {
     const settings = await window.API.request('get_settings');
     if (settings && settings.shop_name) shopName = settings.shop_name;
 } catch(e){}
 
 const now = new Date();
 const generatedText = `Generated: ${window.API.formatDate(now)} - ${now.toLocaleTimeString()}`;
 
 o.items.forEach((item, index) => {
     const slipMain = document.createElement('main');
     slipMain.className = 'pos-slip print-canvas';
     if (index > 0) {
         slipMain.style.pageBreakBefore = 'always';
         slipMain.style.marginTop = '20px';
     }
     
     const garmentText = `${item.clothing_type || 'Custom Item'} (x${item.quantity || 1})`;
     let garmentTextHtml = `<div>${item.clothing_type || 'Custom Item'} (x${item.quantity || 1})</div>`;
     if (item.notes && item.notes.trim() !== '') {
         garmentTextHtml += `<div style="margin-top: 4px; font-size: 0.9em; font-weight: normal;"><strong>Item Note:</strong> ${item.notes}</div>`;
     }
     
     let measurementsHtml = '';
     if (item.measurements && Object.keys(item.measurements).length > 0) {
         const values = item.measurements;
         measurementsHtml += `<div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 0px; margin-top: 8px;">`;
         for (let r = 0; r < 6; r++) {
             for (let c = 0; c < 4; c++) {
                 const sideways_row = 3 - c;
                 const sideways_col = r;
                 const box_number = sideways_row * 6 + sideways_col + 1;
                 const val = values[`Box ${box_number}`] || '';
                 measurementsHtml += `
                     <div style="border: 1px solid #000000; padding: 8px 4px; text-align: center; background-color: #ffffff; min-height: 48px; display: flex; align-items: center; justify-content: center;">
                         ${val.trim() !== '' ? `<div style="font-weight: 600; font-size: 1.5em; color: #000000; writing-mode: vertical-rl; text-orientation: mixed;">${val}</div>` : ''}
                     </div>`;
             }
         }
         measurementsHtml += `</div>`;
     } else {
         measurementsHtml = '<div style="text-align:center; font-style:italic;">No measurements</div>';
     }
     
     slipMain.innerHTML = `
         <div class="text-center mb-2 mt-2">
             <div class="font-bold text-lg">STITCHING SLIP</div>
             <div class="font-bold">${shopName}</div>
         </div>
         <div class="dashed-line"></div>
         <div class="flex-between font-bold" style="font-size: 14px;">
             <span>Bill No:</span><span>${o.order_number || ''}</span>
         </div>
         <div class="flex-between">
             <span>Due:</span><span>${window.API.formatDate(o.delivery_date)}</span>
         </div>
         <div class="dashed-line"></div>
         <div class="font-bold mb-2">Garments:</div>
         <div style="margin-bottom: 5px;">${garmentTextHtml}</div>
         <div class="dashed-line"></div>
         <div class="font-bold text-center mb-2">MEASUREMENTS</div>
         <div style="font-weight: bold; margin-bottom: 2px; text-decoration: underline;">${item.clothing_type || 'Custom Item'} - ${o.order_number || ''}</div>
         ${measurementsHtml}
         <div class="dashed-line"></div>
         <div class="flex-between mt-2" style="font-size: 10px;">
             <span>Cut By: _____</span><span>Sewn By: _____</span>
         </div>
         <div class="text-center mt-2 flex flex-col items-center">
             <div style="font-size: 9px; margin-top: 5px;">${generatedText}</div>
         </div>
     `;
     
     container.appendChild(slipMain);
 });
 
 } catch (e) {
 console.error(e);
 window.API.toast("Failed to load stitching slip: " + e, "error");
 }
}

window.savePdf = async function() {
 let navParamsStr = sessionStorage.getItem("nav_params");
 let navParams = navParamsStr ? JSON.parse(navParamsStr) : null;
 if (!navParams || !navParams.order_id) return;
 
 try {
 const res = await window.API.request('save_pdf', {type: 'slip', order_id: navParams.order_id});
 window.API.toast(res?.message || "Saved successfully!", "success");
 } catch (e) {
 if (e !== "Save cancelled") {
 console.error(e);
 window.API.toast(e, "error");
 }
 }
};

window.printSlip = function() {
 let navParamsStr = sessionStorage.getItem("nav_params");
 let navParams = navParamsStr ? JSON.parse(navParamsStr) : null;
 if (!navParams || !navParams.order_id) {
 window.API.toast("Unable to find order ID for printing.", "error");
 return;
 }
 
 if (window.__triggerMobilePrint) {
 window.__triggerMobilePrint();
 return;
 }
 
 window.API.request('print_pos_document', {type: 'stitching_slip', order_id: navParams.order_id})
 .catch(function(e) {
 console.error(e);
 window.API.toast(e, "error");
 });
};
