
// ---------------------- Mobile tabs handling ----------------------------
function openScreen(screenId) {
    // Oculta todos los divs
    var tabs = document.getElementsByClassName("box");
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].style.zIndex = 0;
    }
  
    // Muestra el div seleccionado
    document.getElementById(screenId).style.zIndex = 20;

    // Elimina la clase 'tab-active' de todos los botones
    var buttons = document.querySelectorAll(".tabs-mobile button");
    for (var i = 0; i < buttons.length; i++) {
        buttons[i].classList.remove("tab-active");
    }
    // Add the 'tab-active' class to the active button/tab
    document.getElementById("btn-" + screenId).classList.add("tab-active");
}

// Function to handle screen size change
function handleResize() {
    if (window.innerWidth > 1500 && window.innerHeight > 680) {
        // Si es escritorio, mostrar los divs
        var tabs = document.getElementsByClassName("box");
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].style.display = "block";
        }
    } else {
        openScreen("screenEditor");
    }
}

function initTabs(){
    if (window.innerWidth > 1500 && window.innerHeight > 680) {
        // Si es escritorio, mostrar los divs
        var tabs = document.getElementsByClassName("box");
        for (var i = 0; i < tabs.length; i++) {
          tabs[i].style.display = "block";
        }
    } else {
        openScreen("screenEditor");
    }
}

// Handle screen size change
window.addEventListener("resize", handleResize);

// Disable long-press text selection inside wasm View
function absorbEvent(event) {
    event.returnValue = false;
}

let div1 = document.querySelector("#screenEditor");
div1.addEventListener("touchstart", absorbEvent);
div1.addEventListener("touchend", absorbEvent);
div1.addEventListener("touchmove", absorbEvent);
div1.addEventListener("touchcancel", absorbEvent);

// User menu style functions
const userMenu     = document.getElementById("user-menu");
const toggleButton = document.getElementById("user-icon");
const dropdownMenu = document.getElementById("user-content");

let userClicked = false
toggleButton.addEventListener("click", function (event) {
    if (!userClicked) {
        dropdownMenu.style.display = "block";
        userMenu.style.background = "#d8e0e8";
    } else {
        dropdownMenu.style.display = "none";
        userMenu.style.background = "gray";
    }
    userClicked = !userClicked;
    event.stopPropagation(); // Prevents the click from propagating to the document
});

document.addEventListener("click", function (event) {
    // Hide the menu if clicking outside the button or menu
    if (!dropdownMenu.contains(event.target) && !toggleButton.contains(event.target)) {
        dropdownMenu.style.display = "none";
        userMenu.style.background = "gray";
    }
    userClicked = false
});

export { openScreen, initTabs }
