/**
 * custom_keypad.js - A custom on-screen keypad mimicking Gboard's Symbols layout
 */

(function() {
    let currentInput = null;
    let keypadEl = null;

    function createKeypad() {
        if (keypadEl) return;

        keypadEl = document.createElement('div');
        keypadEl.id = 'custom-meas-keypad';
        // Tailor it to look like the screenshot (dark theme)
        keypadEl.className = 'fixed bottom-0 left-0 right-0 z-[100] transform translate-y-full transition-transform duration-200 ease-out select-none font-sans';
        keypadEl.style.backgroundColor = '#1e1f24'; // dark background
        keypadEl.style.padding = '8px 4px 8px 4px';
        keypadEl.style.boxShadow = '0 -4px 10px rgba(0,0,0,0.3)';
        
        // Layout matching the screenshot:
        // Left column (math ops): +, -, *, /
        // Main Grid: 
        // 1 2 3 %
        // 4 5 6 -
        // 7 8 9 ⌫
        // ABC , 0 = . ↵
        keypadEl.innerHTML = `
            <div style="display: flex; gap: 8px; max-width: 600px; margin: 0 auto; height: 260px;">
                <!-- Left Sidebar (Math Ops) -->
                <div style="display: flex; flex-direction: column; gap: 8px; width: 50px; background-color: #383944; border-radius: 8px; padding: 4px;">
                    <button class="kp-btn math-btn" data-val="+">+</button>
                    <button class="kp-btn math-btn" data-val="-">-</button>
                    <button class="kp-btn math-btn" data-val="*">*</button>
                    <button class="kp-btn math-btn" data-val="/">/</button>
                </div>
                
                <!-- Main Grid -->
                <div style="display: flex; flex-direction: column; gap: 8px; flex: 1;">
                    <!-- Row 1 -->
                    <div style="display: flex; gap: 8px; flex: 1;">
                        <button class="kp-btn num-btn" data-val="1">1</button>
                        <button class="kp-btn num-btn" data-val="2">2</button>
                        <button class="kp-btn num-btn" data-val="3">3</button>
                        <button class="kp-btn dark-btn" data-val="%">%</button>
                    </div>
                    <!-- Row 2 -->
                    <div style="display: flex; gap: 8px; flex: 1;">
                        <button class="kp-btn num-btn" data-val="4">4</button>
                        <button class="kp-btn num-btn" data-val="5">5</button>
                        <button class="kp-btn num-btn" data-val="6">6</button>
                        <button class="kp-btn dark-btn" data-val=" ">␣</button>
                    </div>
                    <!-- Row 3 -->
                    <div style="display: flex; gap: 8px; flex: 1;">
                        <button class="kp-btn num-btn" data-val="7">7</button>
                        <button class="kp-btn num-btn" data-val="8">8</button>
                        <button class="kp-btn num-btn" data-val="9">9</button>
                        <button class="kp-btn dark-btn action-btn" data-action="backspace">
                            <span class="material-symbols-outlined" style="font-size:22px">backspace</span>
                        </button>
                    </div>
                    <!-- Row 4 -->
                    <div style="display: flex; gap: 8px; flex: 1;">
                        <button class="kp-btn num-btn" data-val="0">0</button>
                        <button class="kp-btn dark-btn" data-val="=">=</button>
                        <button class="kp-btn dark-btn" data-val=".">.</button>
                        <button class="kp-btn action-btn" style="background-color: #383944;" data-action="enter">
                            <span class="material-symbols-outlined" style="font-size:22px">keyboard_return</span>
                        </button>
                    </div>
                </div>
            </div>
            <style>
                .kp-btn {
                    flex: 1;
                    border: none;
                    border-radius: 6px;
                    color: white;
                    font-size: 24px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    cursor: pointer;
                    outline: none;
                    -webkit-tap-highlight-color: transparent;
                }
                .kp-btn:active {
                    opacity: 0.7;
                    background-color: #ffffff40 !important;
                }
                .num-btn {
                    background-color: #353846;
                }
                .dark-btn {
                    background-color: #353846;
                    color: #d1d5db;
                }
                .math-btn {
                    flex: 1;
                    background-color: transparent;
                    color: #9ca3af;
                    font-size: 20px;
                }
            </style>
        `;
        document.body.appendChild(keypadEl);

        // Event listeners for keypad buttons
        keypadEl.addEventListener('touchstart', handleKeypadTouch, {passive: false});
        keypadEl.addEventListener('mousedown', handleKeypadTouch);
    }

    function handleKeypadTouch(e) {
        // Prevent default to avoid losing focus on the input
        e.preventDefault();
        
        let btn = e.target.closest('.kp-btn');
        if (!btn || !currentInput) return;

        // Visual feedback
        const origBg = btn.style.backgroundColor;
        btn.style.backgroundColor = 'rgba(255,255,255,0.3)';
        setTimeout(() => { btn.style.backgroundColor = origBg; }, 100);

        const val = btn.dataset.val;
        const action = btn.dataset.action;

        if (val) {
            insertText(val);
        } else if (action) {
            if (action === 'backspace') {
                deleteText();
            } else if (action === 'enter') {
                moveToNextInput();
            } else if (action === 'abc') {
                switchToABC();
            }
        }
    }

    function insertText(text) {
        if (!currentInput) return;
        const start = currentInput.selectionStart;
        const end = currentInput.selectionEnd;
        const val = currentInput.value;
        currentInput.value = val.substring(0, start) + text + val.substring(end);
        currentInput.setSelectionRange(start + text.length, start + text.length);
        currentInput.dispatchEvent(new Event('input', { bubbles: true }));
    }

    function deleteText() {
        if (!currentInput) return;
        const start = currentInput.selectionStart;
        const end = currentInput.selectionEnd;
        const val = currentInput.value;
        
        if (start === end && start > 0) {
            currentInput.value = val.substring(0, start - 1) + val.substring(end);
            currentInput.setSelectionRange(start - 1, start - 1);
        } else if (start !== end) {
            currentInput.value = val.substring(0, start) + val.substring(end);
            currentInput.setSelectionRange(start, start);
        }
        currentInput.dispatchEvent(new Event('input', { bubbles: true }));
    }

    function moveToNextInput() {
        if (!currentInput) return;
        // Logic specific to new_order.html and add_measurement.html
        const idx = parseInt(currentInput.dataset.idx);
        if (!isNaN(idx)) {
            const nextInput = document.querySelector(\`input[data-idx="\${idx + 1}"]\`);
            if (nextInput) {
                nextInput.focus();
            } else {
                hideKeypad();
                currentInput.blur();
            }
        } else {
            hideKeypad();
            currentInput.blur();
        }
    }

    let isSwitchingToABC = false;

    function switchToABC() {
        if (!currentInput) return;
        isSwitchingToABC = true;
        // Set inputmode='text' so the real Gboard pops up
        currentInput.setAttribute('inputmode', 'text');
        hideKeypad();
        // Blur and focus to trigger real keyboard
        currentInput.blur();
        setTimeout(() => {
            if (currentInput) {
                currentInput.focus();
            }
            setTimeout(() => {
                isSwitchingToABC = false;
            }, 200);
        }, 50);
    }

    function showKeypad() {
        createKeypad();
        keypadEl.style.transform = 'translateY(0)';
    }

    function hideKeypad() {
        if (keypadEl) {
            keypadEl.style.transform = 'translateY(100%)';
        }
    }

    function init() {
        // Intercept touch/click early to forcefully hide native keyboard if switching from Price to Measurement
        document.addEventListener('pointerdown', (e) => {
            const el = e.target;
            if (el && el.classList && (el.classList.contains('meas-input') || el.classList.contains('am-meas-input'))) {
                const active = document.activeElement;
                if (active && active.tagName === 'INPUT' && active !== el && !active.classList.contains('meas-input') && !active.classList.contains('am-meas-input')) {
                    active.blur(); // Hide native keyboard immediately
                }
            }
        }, { capture: true });

        // Handle focusin (fires when tapped since inputs are no longer readonly)
        document.addEventListener('focusin', (e) => {
            const el = e.target;
            if (!el.classList) return;
            if (!el.classList.contains('meas-input') && !el.classList.contains('am-meas-input')) return;

            if (isSwitchingToABC) {
                hideKeypad();
                return;
            }

            // Always reset inputmode to none to ensure Gboard hides/doesn't open
            el.setAttribute('inputmode', 'none');
            
            // Extra safety to force native keyboard close on iOS/Android
            if (document.activeElement === el) {
                // If keyboard is glitching, sometimes a quick blur/focus helps, but usually inputmode=none is enough
                // if we blurred the previous element in pointerdown.
            }

            currentInput = el;
            
            // Show custom keypad
            showKeypad();
        });

        // Handle click just in case focusin was already active on this element
        // (e.g. user tapped outside then tapped back)
        document.addEventListener('click', (e) => {
            const el = e.target;
            if (!el.classList) return;
            if (!el.classList.contains('meas-input') && !el.classList.contains('am-meas-input')) return;

            if (isSwitchingToABC) return;

            el.setAttribute('inputmode', 'none');
            currentInput = el;
            showKeypad();
        }, true);

        // When user taps outside any measurement input (and not on keypad), hide keypad
        document.addEventListener('click', (e) => {
            const el = e.target;
            if (!el.closest || el.closest('#custom-keypad-container')) return; // tap on keypad itself
            if (el.classList && (el.classList.contains('meas-input') || el.classList.contains('am-meas-input'))) return; // tap on input
            
            // Tapped elsewhere — hide keypad
            hideKeypad();
            if (currentInput) {
                // Remove focus so cursor stops blinking
                currentInput.blur();
                currentInput = null;
            }
        });
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
