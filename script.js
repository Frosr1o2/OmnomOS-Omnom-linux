// =============================
// Omnom Linux Website
// script.js
// =============================

// Fade in sections
const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add("show");
        }
    });
}, {
    threshold: 0.15
});

document.querySelectorAll("section").forEach(section => {
    section.classList.add("hidden");
    observer.observe(section);
});

// Back to top button
const topButton = document.createElement("button");
topButton.innerHTML = "↑";
topButton.id = "topButton";
document.body.appendChild(topButton);

topButton.onclick = () => {
    window.scrollTo({
        top: 0,
        behavior: "smooth"
    });
};

window.addEventListener("scroll", () => {
    if (window.scrollY > 500) {
        topButton.classList.add("visible");
    } else {
        topButton.classList.remove("visible");
    }
});

// Mouse glow
const glow = document.createElement("div");
glow.id = "cursorGlow";
document.body.appendChild(glow);

window.addEventListener("mousemove", e => {
    glow.style.left = e.clientX + "px";
    glow.style.top = e.clientY + "px";
});

// Floating particles
const bg = document.getElementById("background");

for (let i = 0; i < 35; i++) {

    const p = document.createElement("span");

    p.className = "particle";

    p.style.left = Math.random() * 100 + "%";

    p.style.top = Math.random() * 100 + "%";

    p.style.animationDuration =
        (10 + Math.random() * 20) + "s";

    p.style.animationDelay =
        (Math.random() * 5) + "s";

    bg.appendChild(p);

}

// Card animation
document.querySelectorAll(".card").forEach(card => {

    card.addEventListener("mousemove", e => {

        const rect = card.getBoundingClientRect();

        const x = e.clientX - rect.left;

        const y = e.clientY - rect.top;

        card.style.background =
        `radial-gradient(circle at ${x}px ${y}px,
        rgba(124,58,237,.25),
        rgba(255,255,255,.05))`;

    });

    card.addEventListener("mouseleave", () => {

        card.style.background =
        "rgba(255,255,255,.06)";

    });

});

// Hero floating
const planet = document.querySelector(".planet");

let angle = 0;

setInterval(() => {

    angle += 0.01;

    planet.style.transform =
        `translateY(${Math.sin(angle) * 12}px)`;

}, 16);

console.log("Omnom Linux website loaded.");
