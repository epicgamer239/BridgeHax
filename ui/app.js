const canvas = document.getElementById('radar-canvas');
const ctx = canvas.getContext('2d');
const jsonDisplay = document.getElementById('json-display');
const latencyDisplay = document.getElementById('latency');
const objCountDisplay = document.getElementById('obj-count');
const visionFpsDisplay = document.getElementById('vision-fps');
const threadCountDisplay = document.getElementById('thread-count');
const threatLevelDisplay = document.getElementById('threat-level');

let isLanyardMode = false;

function resize() {
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
}

window.addEventListener('resize', resize);
resize();

function toggleLanyard() {
    isLanyardMode = !isLanyardMode;
    document.body.classList.toggle('lanyard-active', isLanyardMode);
}

// Mock Data Generation for Demo
const classes = ['car', 'person', 'bicycle', 'bus'];
let objects = [];

function updateMockTelemetry() {
    const count = Math.floor(Math.random() * 4) + 1;
    objects = [];
    
    for (let i = 0; i < count; i++) {
        objects.push({
            object_id: `${classes[Math.floor(Math.random() * classes.length)]}_${100 + i}`,
            class: classes[Math.floor(Math.random() * classes.length)],
            confidence: (0.7 + Math.random() * 0.25).toFixed(2),
            bbox: {
                x_center_norm: (0.2 + Math.random() * 0.6).toFixed(2),
                y_center_norm: (0.4 + Math.random() * 0.4).toFixed(2),
                width_norm: (0.1 + Math.random() * 0.2).toFixed(2),
                height_norm: (0.1 + Math.random() * 0.3).toFixed(2)
            },
            distance_m: (2 + Math.random() * 15).toFixed(1),
            pan_value: (Math.random() * 2 - 1).toFixed(2),
            priority: Math.random() > 0.8 ? "HIGH" : "NORMAL"
        });
    }

    const payload = {
        frame_id: Math.floor(Date.now() / 66),
        timestamp_ms: Date.now(),
        vision_duration_ms: Math.floor(30 + Math.random() * 15),
        objects: objects
    };

    // Update UI
    jsonDisplay.textContent = JSON.stringify(payload, null, 2);
    latencyDisplay.textContent = payload.vision_duration_ms + 12; // Vision + Audio + Bridge
    objCountDisplay.textContent = objects.length;
    visionFpsDisplay.textContent = (1000 / payload.vision_duration_ms).toFixed(1);
    threadCountDisplay.textContent = objects.length;

    const hasHighPriority = objects.some(o => o.priority === "HIGH" || parseFloat(o.distance_m) < 4);
    threatLevelDisplay.textContent = hasHighPriority ? "CRITICAL" : "LOW";
    threatLevelDisplay.parentElement.style.borderColor = hasHighPriority ? "var(--danger)" : "var(--accent)";
}

function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw Radar Rings (Subtle)
    ctx.strokeStyle = 'rgba(0, 255, 136, 0.05)';
    ctx.lineWidth = 1;
    for (let i = 1; i <= 4; i++) {
        ctx.beginPath();
        ctx.arc(canvas.width / 2, canvas.height, (canvas.height / 4) * i, Math.PI, 0);
        ctx.stroke();
    }

    // Draw Objects
    objects.forEach(obj => {
        const x = obj.bbox.x_center_norm * canvas.width;
        const y = obj.bbox.y_center_norm * canvas.height;
        const w = obj.bbox.width_norm * canvas.width;
        const h = obj.bbox.height_norm * canvas.height;

        const isThreat = parseFloat(obj.distance_m) < 4;
        const color = isThreat ? '#FF4D4D' : '#00FF88';

        // Bounding Box
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.strokeRect(x - w/2, y - h/2, w, h);

        // Label
        ctx.fillStyle = color;
        ctx.font = '12px JetBrains Mono';
        ctx.fillText(`${obj.class.toUpperCase()} [${obj.distance_m}m]`, x - w/2, y - h/2 - 5);

        // Audio Clone Pulse
        const pulseSize = (Math.sin(Date.now() / 200) + 1) * 5;
        ctx.beginPath();
        ctx.arc(x, y, 10 + pulseSize, 0, Math.PI * 2);
        ctx.fillStyle = isThreat ? 'rgba(255, 77, 77, 0.2)' : 'rgba(0, 255, 136, 0.2)';
        ctx.fill();
        
        // Distance Line to center bottom (Listener)
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(canvas.width / 2, canvas.height);
        ctx.strokeStyle = isThreat ? 'rgba(255, 77, 77, 0.3)' : 'rgba(0, 255, 136, 0.1)';
        ctx.setLineDash([5, 5]);
        ctx.stroke();
        ctx.setLineDash([]);
    });

    requestAnimationFrame(draw);
}

setInterval(updateMockTelemetry, 500);
draw();
