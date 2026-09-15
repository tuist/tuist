defmodule TuistWeb.Marketing.Components.Posts.NewTuist.RackScene do
  @moduledoc """
  An anonymized, interactive rack model for the "Down to the metal" section of
  the new Tuist post.

  The scene keeps the materials, lighting, proportions, and presentation of the
  original design while omitting location names, dimensions, capacities, device
  labels, and power topology.
  """
  use TuistWeb, :live_component

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="rack-scene"] {
        --rack-background: var(--noora-surface-background-primary);
        position: relative;
        display: block;
        box-sizing: border-box;
        margin: var(--noora-spacing-9) 0;
        width: 100%;
        overflow: hidden;
        border: 1px solid var(--marketing-stroke-default);
        border-radius: 12px;
        background: var(--rack-background);
        color: #eeedf1;

        & [data-part="stage"] {
          position: relative;
          width: 100%;
          height: clamp(440px, 76vw, 620px);
          overflow: hidden;
          cursor: grab;
          touch-action: none;
        }

        & [data-part="stage"]:active { cursor: grabbing; }
        & canvas {
          display: block !important;
          width: 100% !important;
          height: 100% !important;
          outline: none;
        }

        & [data-part="hint"] {
          position: absolute;
          z-index: 1;
          right: var(--noora-spacing-6);
          bottom: var(--noora-spacing-5);
          color: var(--noora-surface-label-tertiary);
          font-size: 0.625rem;
          pointer-events: none;
        }

        & [data-part="loading"] {
          position: absolute;
          z-index: 2;
          inset: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--rack-background);
          color: var(--noora-surface-label-secondary);
          font-size: 0.75rem;
        }

        @media (max-width: 480px) {
          & [data-part="stage"] { height: 440px; }
          & [data-part="hint"] { display: none; }
        }
      }
    </style>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".RackScene">
      const THREE_URL = "https://esm.sh/three@0.180.0";
      const CONTROLS_URL = "https://esm.sh/three@0.180.0/examples/jsm/controls/OrbitControls.js";
      const ROUNDED_BOX_URL = "https://esm.sh/three@0.180.0/examples/jsm/geometries/RoundedBoxGeometry.js";
      const ROOM_URL = "https://esm.sh/three@0.180.0/examples/jsm/environments/RoomEnvironment.js";
      const loadModule = (url) => import(url);

      export default {
        mounted() {
          this.stage = this.el.querySelector('[data-part="stage"]');
          this.loading = this.el.querySelector('[data-part="loading"]');
          this.disposed = false;
          this.boot().catch((error) => {
            console.error("Rack scene load failed", error);
            if (this.loading) this.loading.textContent = "Unable to load the rack model";
          });
        },

        destroyed() {
          this.disposed = true;
          cancelAnimationFrame(this.animationFrame);
          this.resizeObserver?.disconnect();
          this.controls?.dispose();
          this.scene?.traverse((object) => {
            object.geometry?.dispose?.();
            const materials = Array.isArray(object.material) ? object.material : [object.material];
            materials.filter(Boolean).forEach((material) => material.dispose?.());
          });
          this.environmentTarget?.dispose?.();
          this.logoTexture?.dispose?.();
          this.renderer?.dispose?.();
          this.renderer?.domElement?.remove();
        },

        async boot() {
          const [THREE, { OrbitControls }, { RoundedBoxGeometry }, { RoomEnvironment }] =
            await Promise.all([
              loadModule(THREE_URL), loadModule(CONTROLS_URL),
              loadModule(ROUNDED_BOX_URL), loadModule(ROOM_URL),
            ]);
          if (this.disposed) return;

          const scene = new THREE.Scene();
          this.scene = scene;

          const renderer = new THREE.WebGLRenderer({
            antialias: true, alpha: true, powerPreference: "high-performance",
          });
          renderer.setClearColor(0x000000, 0);
          renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.8));
          renderer.shadowMap.enabled = true;
          renderer.shadowMap.type = THREE.PCFSoftShadowMap;
          renderer.outputColorSpace = THREE.SRGBColorSpace;
          renderer.toneMapping = THREE.ACESFilmicToneMapping;
          renderer.toneMappingExposure = 1.18;
          renderer.domElement.tabIndex = 0;
          renderer.domElement.setAttribute("aria-label", "Interactive three-dimensional rack model");
          this.stage.appendChild(renderer.domElement);
          this.renderer = renderer;

          const camera = new THREE.PerspectiveCamera(34, 1, 0.015, 70);
          this.camera = camera;
          const controls = new OrbitControls(camera, renderer.domElement);
          controls.enableDamping = true;
          controls.dampingFactor = 0.085;
          controls.enablePan = false;
          controls.minDistance = 2.2;
          controls.maxDistance = 7;
          controls.maxPolarAngle = Math.PI * 0.91;
          controls.target.set(0, 1.1, 0);
          this.controls = controls;

          const environmentGenerator = new THREE.PMREMGenerator(renderer);
          const room = new RoomEnvironment();
          const environmentTarget = environmentGenerator.fromScene(room, 0.04);
          scene.environment = environmentTarget.texture;
          scene.environmentIntensity = 0.48;
          room.dispose();
          environmentGenerator.dispose();
          this.environmentTarget = environmentTarget;

          const key = new THREE.DirectionalLight("#ffffff", 4.3);
          key.position.set(2.5, 4.2, 3.6);
          key.castShadow = true;
          key.shadow.mapSize.set(1024, 1024);
          key.shadow.camera.left = -2;
          key.shadow.camera.right = 2;
          key.shadow.camera.top = 3;
          key.shadow.camera.bottom = -2;
          key.shadow.camera.far = 12;
          key.shadow.bias = -0.0001;
          key.shadow.normalBias = 0.004;
          key.target.position.set(0, 1, 0);
          scene.add(key, key.target);
          const fill = new THREE.DirectionalLight("#b6cfff", 1.7);
          fill.position.set(-2, 1.8, 1.2);
          scene.add(fill);
          const rim = new THREE.DirectionalLight("#b9a2f0", 2.4);
          rim.position.set(-1.8, 3, -3);
          scene.add(rim);
          scene.add(new THREE.HemisphereLight("#d6dcea", "#242027", 0.45));

          const floorShadow = new THREE.Mesh(
            new THREE.PlaneGeometry(12, 12), new THREE.ShadowMaterial({ opacity: 0.2 })
          );
          floorShadow.rotation.x = -Math.PI / 2;
          floorShadow.position.y = -0.007;
          floorShadow.receiveShadow = true;
          scene.add(floorShadow);
          const grid = new THREE.GridHelper(12, 20, "#dedde5", "#e9e8ef");
          grid.position.y = -0.006;
          grid.material.transparent = true;
          grid.material.opacity = 0.5;
          scene.add(grid);
          this.logoTexture = new THREE.TextureLoader().load(this.el.dataset.logoSrc);
          this.logoTexture.colorSpace = THREE.SRGBColorSpace;
          scene.add(this.buildRack(THREE, RoundedBoxGeometry));

          const resize = () => {
            const { width, height } = this.stage.getBoundingClientRect();
            renderer.setSize(width, height, false);
            camera.aspect = width / height;
            camera.updateProjectionMatrix();
            camera.position.copy(this.viewPosition(THREE, camera, width / height));
            controls.update();
          };
          this.resizeObserver = new ResizeObserver(resize);
          this.resizeObserver.observe(this.stage);
          resize();
          this.loading?.remove();

          const render = () => {
            if (this.disposed) return;
            controls.update();
            renderer.render(scene, camera);
            this.animationFrame = requestAnimationFrame(render);
          };
          render();
        },

        viewPosition(THREE, camera, aspect) {
          const direction = new THREE.Vector3(0.4, 0.19, 0.92).normalize();
          const target = new THREE.Vector3(0, 1.1, 0);
          const right = new THREE.Vector3(direction.z, 0, -direction.x).normalize();
          const up = new THREE.Vector3().crossVectors(direction, right);
          const tangent = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
          let distance = 0;
          for (const x of [-0.33, 0.33]) for (const y of [0, 2.22]) for (const z of [-0.62, 0.62]) {
            const point = new THREE.Vector3(x, y, z).sub(target);
            distance = Math.max(distance, point.dot(direction) + 1.17 * Math.max(
              Math.abs(point.dot(up)) / tangent,
              Math.abs(point.dot(right)) / (tangent * aspect)
            ));
          }
          return target.addScaledVector(direction, distance);
        },

        buildRack(THREE, RoundedBoxGeometry) {
          const rack = new THREE.Group();
          const boxGeometry = new THREE.BoxGeometry(1, 1, 1);
          const cylinderGeometry = new THREE.CylinderGeometry(1, 1, 1, 12);
          const roundGeometry = new RoundedBoxGeometry(1, 1, 1, 3, 0.115);
          const miniGeometry = new RoundedBoxGeometry(0.127, 0.05, 0.127, 5, 0.014);
          const material = (color, roughness = 0.7, metalness = 0.35) =>
            new THREE.MeshStandardMaterial({ color, roughness, metalness });
          const materials = {
            frame: material("#6f2cff", 0.68, 0.38), rail: material("#8e62ff", 0.5, 0.55),
            tray: material("#202124", 0.75, 0.4), dark: material("#08090b", 0.9, 0.1),
            silver: material("#c8c9cd", 0.35, 0.9), steel: material("#77808d", 0.34, 0.85),
            violet: material("#6f2cff", 0.4, 0.6), slot: material("#07080a", 0.7, 0.25),
            plastic: material("#25282c", 0.9, 0.05), rubber: material("#0d0d10", 0.92, 0.05),
            kit: material("#85858d", 0.56, 0.72), top: material("#9c9da2", 0.37, 0.85),
          };
          const box = (parent, width, height, depth, x, y, z, boxMaterial = materials.tray) => {
            const mesh = new THREE.Mesh(boxGeometry, boxMaterial);
            mesh.scale.set(width, height, depth);
            mesh.position.set(x, y, z);
            mesh.castShadow = true;
            mesh.receiveShadow = true;
            parent.add(mesh);
            return mesh;
          };
          const rounded = (parent, width, height, depth, x, y, z, boxMaterial) => {
            const mesh = new THREE.Mesh(roundGeometry, boxMaterial);
            mesh.scale.set(width, height, depth);
            mesh.position.set(x, y, z);
            mesh.castShadow = true;
            mesh.receiveShadow = true;
            parent.add(mesh);
            return mesh;
          };
          const screw = (x, y, z) => {
            const head = new THREE.Mesh(cylinderGeometry, materials.steel);
            head.scale.set(0.003, 0.0017, 0.003);
            head.rotation.x = Math.PI / 2;
            head.position.set(x, y, z);
            rack.add(head);
            box(rack, 0.0033, 0.0007, 0.0004, x, y, z + 0.001, materials.dark);
          };
          const cabinetWidth = 0.6, cabinetDepth = 1.2, cabinetHeight = 2.2, front = 0.549;

          for (const x of [-cabinetWidth / 2 + 0.014, cabinetWidth / 2 - 0.014]) {
            for (const z of [-cabinetDepth / 2 + 0.014, cabinetDepth / 2 - 0.014]) {
              box(rack, 0.028, cabinetHeight - 0.03, 0.028, x, cabinetHeight / 2 + 0.015, z, materials.frame);
              box(rack, 0.05, 0.016, 0.065, x, 0.008, z, materials.rubber);
            }
          }
          for (const y of [0.033, cabinetHeight - 0.018]) {
            for (const z of [-0.583, 0.583]) box(rack, 0.572, 0.035, 0.035, 0, y, z, materials.frame);
            for (const x of [-0.283, 0.283]) box(rack, 0.035, 0.035, 1.132, x, y, 0, materials.frame);
          }
          for (const x of [-0.235, 0.235]) {
            box(rack, 0.024, 2.08, 0.017, x, 1.08, front - 0.007, materials.rail);
            box(rack, 0.024, 2.08, 0.017, x, 1.08, -0.421, materials.rail);
            for (let index = 0; index < 48; index++) {
              box(rack, 0.011, 0.003, 0.004, x, 0.065 + index * 0.043, front + 0.004, materials.dark);
            }
          }
          box(rack, 0.43, 0.032, 0.5, 0, cabinetHeight - 0.046, -0.01, materials.frame);
          for (let index = 0; index < 4; index++) {
            const ring = new THREE.Mesh(new THREE.RingGeometry(0.027, 0.032, 24), materials.rail);
            ring.rotation.x = -Math.PI / 2;
            ring.position.set(-0.14 + index * 0.094, cabinetHeight - 0.029, 0);
            rack.add(ring);
          }

          const addFaceplate = (y, height, faceMaterial = materials.tray) => {
            box(rack, 0.483, height, 0.012, 0, y, front, faceMaterial);
            for (const x of [-0.233, 0.233]) screw(x, y, front + 0.008);
          };
          const addVents = (y, count) => {
            for (let index = 0; index < count; index++) {
              box(rack, 0.006, 0.016, 0.002, -0.19 + index * (0.38 / (count - 1)), y, front + 0.008, materials.slot);
            }
          };
          addFaceplate(2.122, 0.041);
          for (let index = 0; index < 24; index++) {
            const x = -0.198 + index * 0.0172;
            box(rack, 0.013, 0.012, 0.007, x, 2.129, front + 0.008, materials.plastic);
            box(rack, 0.009, 0.008, 0.002, x, 2.129, front + 0.012, materials.slot);
          }
          addVents(2.11, 52);
          for (const y of [2.078, 2.033]) {
            addFaceplate(y, 0.041);
            for (let index = 0; index < 24; index++) {
              const x = -0.147 + index * 0.0136;
              box(rack, 0.0106, 0.0115, 0.004, x, y + 0.003, front + 0.008, materials.steel);
              box(rack, 0.0082, 0.008, 0.002, x, y + 0.0037, front + 0.011, materials.slot);
            }
            addVents(y - 0.013, 32);
          }
          addFaceplate(1.989, 0.041, materials.dark);

          box(rack, 0.444, 0.004, 0.52, 0, 1.878, front - 0.26, materials.tray);
          const serviceMini = new THREE.Mesh(miniGeometry, materials.silver);
          serviceMini.position.set(-0.151, 1.911, front - 0.075);
          serviceMini.castShadow = true;
          rack.add(serviceMini);
          for (let index = 0; index < 2; index++) {
            rounded(rack, 0.09, 0.025, 0.06, -0.024, 1.895, front - 0.046 - index * 0.081, materials.plastic);
          }
          rounded(rack, 0.15, 0.04, 0.15, 0.135, 1.902, front - 0.088, materials.rail);

          for (const y of [1.856, 1.811]) {
            addFaceplate(y, 0.041, materials.violet);
            for (let index = 0; index < 4; index++) {
              const x = -0.132 + index * 0.088;
              rounded(rack, 0.08, 0.027, 0.008, x, y - 0.002, front + 0.01, materials.dark);
              box(rack, 0.058, 0.02, 0.005, x - 0.007, y - 0.002, front + 0.015, materials.tray);
              box(rack, 0.006, 0.021, 0.006, x + 0.031, y - 0.002, front + 0.017, materials.steel);
            }
          }
          addFaceplate(1.767, 0.041, materials.dark);
          addVents(1.767, 52);
          for (let index = 0; index < 6; index++) {
            addFaceplate(1.722 - index * 0.04445, 0.041, materials.dark);
          }

          const logoMaterial = new THREE.MeshBasicMaterial({
            map: this.logoTexture, transparent: true, depthWrite: false, toneMapped: false,
          });
          logoMaterial.color.setRGB(2.55, 2.2, 0.92);
          const logo = new THREE.Mesh(new THREE.PlaneGeometry(0.026, 0.026), logoMaterial);
          logo.position.set(0.185, 1.989, front + 0.008);
          rack.add(logo);

          const kitShape = new THREE.Shape();
          kitShape.moveTo(-0.2415, -0.029);
          kitShape.lineTo(0.2415, -0.029);
          kitShape.lineTo(0.2415, 0.029);
          kitShape.lineTo(-0.2415, 0.029);
          kitShape.closePath();
          for (const centerX of [-0.0705, 0.0705]) {
            const width = 0.132, height = 0.052, radius = 0.008;
            const x = centerX - width / 2, y = -height / 2;
            const opening = new THREE.Path();
            opening.moveTo(x + radius, y);
            opening.lineTo(x + width - radius, y);
            opening.quadraticCurveTo(x + width, y, x + width, y + radius);
            opening.lineTo(x + width, y + height - radius);
            opening.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
            opening.lineTo(x + radius, y + height);
            opening.quadraticCurveTo(x, y + height, x, y + height - radius);
            opening.lineTo(x, y + radius);
            opening.quadraticCurveTo(x, y, x + radius, y);
            kitShape.holes.push(opening);
          }
          const kitGeometry = new THREE.ExtrudeGeometry(kitShape, {
            depth: 0.002, bevelEnabled: false, curveSegments: 5,
          });

          const addMiniKit = (y) => {
            const face = new THREE.Mesh(kitGeometry, materials.kit);
            face.position.set(0, y, front);
            face.castShadow = true;
            face.receiveShadow = true;
            rack.add(face);
            box(rack, 0.444, 0.002, 0.21, 0, y - 0.028, front - 0.105, materials.tray);
            for (const x of [-0.221, 0.221]) {
              box(rack, 0.003, 0.022, 0.21, x, y - 0.018, front - 0.105, materials.tray);
              box(rack, 0.008, 0.012, 0.194, x, y - 0.017, front - 0.105, materials.rail);
            }
            for (const x of [-0.0705, 0.0705]) {
              const mini = new THREE.Mesh(miniGeometry, materials.silver);
              mini.position.set(x, y, front - 0.064);
              mini.castShadow = true;
              mini.receiveShadow = true;
              rack.add(mini);
              const foot = new THREE.Mesh(cylinderGeometry, materials.rubber);
              foot.scale.set(0.047, 0.004, 0.047);
              foot.position.set(x, y - 0.025, front - 0.064);
              rack.add(foot);
              const topMark = new THREE.Mesh(cylinderGeometry, materials.top);
              topMark.scale.set(0.009, 0.00035, 0.009);
              topMark.position.set(x, y + 0.0254, front - 0.064);
              rack.add(topMark);
              for (const offset of [-0.006, 0.01]) {
                rounded(rack, 0.007, 0.003, 0.0013, x + offset, y - 0.005, front + 0.0002, materials.slot);
              }
            }
            for (const side of [-1, 1]) for (let index = 0; index < 6; index++) {
              const x = side * (0.158 + (index % 3) * 0.022);
              const portY = y + (index < 3 ? 0.008 : -0.009);
              box(rack, 0.016, 0.012, 0.003, x, portY, front + 0.0032, materials.plastic);
              box(rack, 0.011, 0.008, 0.0008, x, portY, front + 0.005, materials.dark);
            }
            for (const x of [-0.232, 0.232]) for (const offsetY of [-0.018, 0.018]) {
              screw(x, y + offsetY, front + 0.003);
            }
          };
          for (let index = 0; index < 12; index++) addMiniKit(1.448 - index * 0.05927);

          addMiniKit(0.707);
          addFaceplate(0.67, 0.025, materials.rail);
          for (let index = 0; index < 14; index++) {
            addFaceplate(0.656 - index * 0.04445, 0.041, materials.dark);
          }

          const cableMaterial = material("#6f2cff", 0.5, 0.2);
          for (let index = 0; index < 5; index++) {
            const start = new THREE.Vector3(-0.205, 1.78 - index * 0.025, front - 0.11);
            const end = new THREE.Vector3(-0.21, 1.58 - index * 0.14, -0.42);
            const curve = new THREE.CatmullRomCurve3([
              start, new THREE.Vector3(-0.255, start.y - 0.04, 0.25),
              new THREE.Vector3(-0.255, end.y + 0.04, -0.2), end,
            ]);
            const cable = new THREE.Mesh(new THREE.TubeGeometry(curve, 36, 0.004, 7, false), cableMaterial);
            cable.castShadow = true;
            rack.add(cable);
          }
          return rack;
        },
      };
    </script>

    <div
      id={@id}
      data-part="rack-scene"
      data-logo-src={~p"/marketing/images/brand/tuist-logo.svg"}
      phx-hook=".RackScene"
      phx-update="ignore"
    >
      <div
        data-part="stage"
        role="img"
        aria-label="An interactive, anonymized model of a Tuist compute and storage rack"
        title="Drag to orbit and scroll to zoom"
      >
        <div data-part="hint">Drag to orbit · Scroll to zoom</div>
        <div data-part="loading">Assembling rack…</div>
      </div>
    </div>
    """
  end
end
