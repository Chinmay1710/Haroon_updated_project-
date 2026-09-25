/**
 * web_api_shim.js - Replaces QWebChannel bridge with REST API calls.
 * 
 * This file is ONLY loaded when pages are accessed via browser (not Qt WebEngine).
 * It creates a fake pyBridge object and overrides window.API.request() to use fetch().
 *
 * Zero changes to existing page JS required!
 */
(function() {
    'use strict';

    // ─── Detect if we're in Qt WebEngine or a regular browser ─────────
    // If QWebChannel is available, we're in desktop mode - don't load the shim
    if (typeof QWebChannel !== 'undefined' && typeof qt !== 'undefined') {
        console.log('[Shim] Qt WebEngine detected, shim not needed.');
        return;
    }

    console.log('[Shim] Browser mode detected. Activating REST API shim...');

    // ─── Page mapping for navigation ──────────────────────────────────
    var PAGE_MAP = {
        'dashboard': '/app/dashboard.html',
        'customers_list': '/app/customers_list.html',
        'customer_details': '/app/customer_details.html',
        'add_customer': '/app/add_customer.html',
        'measurements_list': '/app/measurements_list.html',
        'add_measurement': '/app/add_measurement.html',
        'orders_list': '/app/orders_list.html',
        'new_order': '/app/new_order.html',
        'order_details': '/app/order_details.html',
        'payments': '/app/payments.html',
        'add_payment': '/app/add_payment.html',
        'deliveries': '/app/deliveries.html',
        'expenses_list': '/app/expenses_list.html',
        'add_expense': '/app/add_expense.html',
        'workers': '/app/workers.html',
        'stock_list': '/app/stock_list.html',
        'reports': '/app/reports.html',
        'settings': '/app/settings.html',
        'backup_restore': '/app/backup_restore.html',
        'receipt_preview': '/app/receipt_preview.html',
        'stitching_slip_preview': '/app/stitching_slip_preview.html',
    };

    // ─── Create fake pyBridge so app.js doesn't error ─────────────────
    window.pyBridge = {
        log: function(msg) { console.log('[JS-Shim]', msg); },
        dispatch: function(action, payloadStr, callback) {
            var payload = {};
            try { payload = JSON.parse(payloadStr || '{}'); } catch(e) {}

            // Handle navigation client-side
            if (action === 'navigate_to') {
                var page = payload.page || 'dashboard';
                var url = PAGE_MAP[page];
                if (url) {
                    // Pass any extra params
                    var params = new URLSearchParams();
                    Object.keys(payload).forEach(function(k) {
                        if (k !== 'page') params.set(k, payload[k]);
                    });
                    var qs = params.toString();
                    window.location.href = url + (qs ? '?' + qs : '');
                }
                if (callback) callback(JSON.stringify({status: 'success'}));
                return;
            }

            // Handle copy_to_clipboard on mobile
            if (action === 'copy_to_clipboard') {
                var text = payload.text || '';
                if (navigator.clipboard) {
                    navigator.clipboard.writeText(text).catch(function(){});
                }
                if (callback) callback(JSON.stringify({status: 'success'}));
                return;
            }

            // Handle open_url on mobile
            if (action === 'open_url') {
                var openUrl = payload.url || '';
                if (openUrl) window.location.href = openUrl;
                if (callback) callback(JSON.stringify({status: 'success'}));
                return;
            }

            // Handle open_whatsapp_url on mobile
            if (action === 'open_whatsapp_url') {
                var waUrl = payload.url || '';
                if (waUrl) {
                    // Convert whatsapp:// to https://wa.me/ for mobile browser compatibility
                    if (waUrl.startsWith('whatsapp://send?')) {
                        var waParams = new URLSearchParams(waUrl.replace('whatsapp://send?', ''));
                        waUrl = 'https://wa.me/' + waParams.get('phone') + '?text=' + waParams.get('text');
                    }
                    window.location.href = waUrl;
                }
                if (callback) callback(JSON.stringify({status: 'success'}));
                return;
            }

            // Handle print commands on mobile browser
            if (action === 'print_pos_document' || action === 'print_receipt') {
                window.print();
                if (callback) callback(JSON.stringify({status: 'success'}));
                return;
            }

            // All other actions -> REST API
            fetch('/admin-api/dispatch', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: action, payload: payload })
            })
            .then(function(res) { return res.json(); })
            .then(function(data) {
                if (callback) callback(JSON.stringify(data));
            })
            .catch(function(err) {
                console.error('[Shim] API error for', action, ':', err);
                if (callback) callback(JSON.stringify({
                    status: 'error', 
                    message: 'Network error: ' + err.message
                }));
            });
        },
        // Fake signal connections (no-op on mobile)
        notification_requested: { connect: function(){} },
        customer_added: { connect: function(){} },
        order_added: { connect: function(){} },
        dictation_result_requested: { connect: function(){} },
    };

    // ─── Override window.API.request to use REST API ──────────────────
    // (api.js sets this up, but we override it before page scripts run)
    
    // Wait for DOMContentLoaded to override after api.js has loaded
    var _originalDOMReady = [];
    
    // We need to intercept before app.js tries to use QWebChannel
    // Create a fake QWebChannel constructor
    window.QWebChannel = undefined;

    // Override after DOM is ready (api.js would have set up window.API)
    document.addEventListener('DOMContentLoaded', function() {
        // Ensure window.API exists
        if (!window.API) {
            window.API = {};
        }

        // Override the request method
        window.API.request = function(action, payload) {
            payload = payload || {};
            
            return new Promise(function(resolve, reject) {
                // Handle navigation client-side
                if (action === 'navigate_to' && payload) {
                    sessionStorage.setItem('nav_params', JSON.stringify(payload));
                    var page = payload.page || 'dashboard';
                    var url = PAGE_MAP[page];
                    if (url) {
                        var params = new URLSearchParams();
                        Object.keys(payload).forEach(function(k) {
                            if (k !== 'page') params.set(k, payload[k]);
                        });
                        var qs = params.toString();
                        window.location.href = url + (qs ? '?' + qs : '');
                    }
                    resolve({});
                    return;
                }

                // Handle copy_to_clipboard
                if (action === 'copy_to_clipboard') {
                    if (navigator.clipboard && payload.text) {
                        navigator.clipboard.writeText(payload.text).catch(function(){});
                    }
                    resolve({});
                    return;
                }

                // Handle open_url
                if (action === 'open_url') {
                    if (payload.url) window.location.href = payload.url;
                    resolve({});
                    return;
                }

                // Handle open_whatsapp_url
                if (action === 'open_whatsapp_url') {
                    var waUrl = payload.url || '';
                    if (waUrl) {
                        if (waUrl.startsWith('whatsapp://send?')) {
                            var waParams = new URLSearchParams(waUrl.replace('whatsapp://send?', ''));
                            waUrl = 'https://wa.me/' + waParams.get('phone') + '?text=' + waParams.get('text');
                        }
                        window.location.href = waUrl;
                    }
                    resolve({});
                    return;
                }

                // Handle print commands on mobile browser
                if (action === 'print_pos_document' || action === 'print_receipt' || action === 'print_stitching_slip') {
                    // Extract the print container
                    var printCanvas = document.querySelector('.print-canvas');
                    if (printCanvas) {
                        // Gather essential styles to embed
                        var essentialStyles = `
                            body { font-family: 'Arial', sans-serif; color: black; background: white; margin: 0; padding: 10px; width: 100%; box-sizing: border-box; }
                            .dashed-line { border-top: 2px dashed #000; margin: 8px 0; }
                            .flex-between { display: flex; justify-content: space-between; align-items: flex-start; }
                            .text-center { text-align: center; }
                            .text-right { text-align: right; }
                            .font-bold { font-weight: bold; }
                            .text-lg { font-size: 24px; font-weight: bold; }
                            table { width: 100%; border-collapse: collapse; margin: 8px 0; }
                            th, td { padding: 4px 0; font-size: 16px; }
                            th { text-align: left; border-bottom: 2px dashed #000; border-top: 2px dashed #000; }
                            .pos-receipt, .pos-slip { width: 100%; max-width: 100%; padding-bottom: 40px; }
                            /* Mobile classes just in case */
                            .flex-col { display: flex; flex-direction: column; }
                            .items-center { align-items: center; }
                            .mt-2 { margin-top: 8px; }
                            .mb-2 { margin-bottom: 8px; }
                        `;
                        
                        var htmlContent = '<!DOCTYPE html><html><head><style>' + essentialStyles + '</style></head><body>' + printCanvas.outerHTML + '</body></html>';
                        var encodedContent = encodeURIComponent(htmlContent);
                        var intentUrl = "intent://#Intent;scheme=rawbt;package=ru.a402d.rawbtprinter;action=android.intent.action.VIEW;type=text/html;S.android.intent.extra.TEXT=" + encodedContent + ";end";
                        
                        // Fallback to standard window.print() if RawBT intent fails to trigger
                        var iframe = document.createElement('iframe');
                        iframe.style.display = 'none';
                        iframe.src = intentUrl;
                        document.body.appendChild(iframe);
                        
                        // We also set timeout to try normal print if rawbt didn't intercept it
                        setTimeout(function() {
                            document.body.removeChild(iframe);
                            window.print();
                        }, 1000);
                        
                    } else {
                        // Fallback if no print canvas
                        window.print();
                    }
                    
                    resolve({status: 'success'});
                    return;
                }

                // All other actions -> REST API call
                fetch('/admin-api/dispatch', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: action, payload: payload })
                })
                .then(function(res) { return res.json(); })
                .then(function(response) {
                    if (response.status === 'success') {
                        resolve(response.data);
                    } else {
                        console.error('[Shim] API Error [' + action + ']:', response.message);
                        reject(response.message || 'Unknown error occurred.');
                    }
                })
                .catch(function(err) {
                    console.error('[Shim] Network error for', action, ':', err);
                    reject('Network error: ' + err.message);
                });
            });
        };

        // Also override navigate helper
        window.API.navigate = function(page) {
            window.API.request('navigate_to', { page: page });
        };

        // ─── Fix sidebar navigation for browser mode ──────────────────
        var navLinks = document.querySelectorAll('a[href="#"]');
        navLinks.forEach(function(link) {
            link.addEventListener('click', function(e) {
                e.preventDefault();
                var navTarget = this.getAttribute('data-nav');
                if (navTarget) {
                    window.API.navigate(navTarget);
                } else {
                    // Text-based matching fallback (same as app.js)
                    var text = this.innerText.toLowerCase().trim();
                    if (text.includes('dashboard') || text.includes('डैशबोर्ड')) window.API.navigate('dashboard');
                    else if (text.includes('customer') || text.includes('ग्राहक')) window.API.navigate('customers_list');
                    else if (text.includes('measurement') || text.includes('माप')) window.API.navigate('measurements_list');
                    else if (text.includes('order') || text.includes('ऑर्डर')) window.API.navigate('orders_list');
                    else if (text.includes('payment') || text.includes('भुगतान')) window.API.navigate('payments');
                    else if (text.includes('deliveries') || text.includes('डिलीवरी')) window.API.navigate('deliveries');
                    else if (text.includes('expense') || text.includes('खर्च')) window.API.navigate('expenses_list');
                    else if (text.includes('report') || text.includes('रिपोर्ट')) window.API.navigate('reports');
                    else if (text.includes('worker') || text.includes('कर्मचारी')) window.API.navigate('workers');
                    else if (text.includes('stock') || text.includes('स्टॉक')) window.API.navigate('stock_list');
                    else if (text.includes('setting') || text.includes('सेटिंग')) window.API.navigate('settings');
                    else if (text.includes('backup') || text.includes('बैकअप')) window.API.navigate('backup_restore');
                }
            });
        });

        // Apply global settings
        setTimeout(function() {
            if (window.applyGlobalSettings) {
                window.applyGlobalSettings();
            } else {
                // Manually apply if applyGlobalSettings is not defined (shim loaded before app.js)
                window.API.request('get_settings').then(function(settings) {
                    if (settings) {
                        document.querySelectorAll('.global-shop-name').forEach(function(el) {
                            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') el.value = settings.shop_name;
                            else el.textContent = settings.shop_name;
                        });
                        document.querySelectorAll('.global-shop-phone').forEach(function(el) {
                            el.textContent = settings.phone || '';
                        });
                        document.querySelectorAll('.global-shop-address').forEach(function(el) {
                            el.textContent = settings.address || '';
                        });
                    }
                }).catch(function(){});
            }
        }, 200);

        console.log('[Shim] REST API shim fully active. All bridge calls routed to /admin-api/dispatch');
    });

    // ─── Global dispatchToPython replacement ──────────────────────────
    window.dispatchToPython = function(action, payload) {
        if (window.pyBridge) {
            window.pyBridge.dispatch(action, JSON.stringify(payload || {}));
        }
    };

})();
