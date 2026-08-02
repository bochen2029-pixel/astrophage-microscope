// src/render/gl_context.cpp
#include "render/gl_context.h"

#include <cstdio>

#include <glad/gl.h>
#include <GLFW/glfw3.h>

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_opengl3.h"

namespace astro::render {

namespace {

GlContext* g_debug_target = nullptr;   // composition-root singleton; app owns one context

void APIENTRY gl_debug_callback(GLenum, GLenum type, GLuint id, GLenum severity,
                                GLsizei, const GLchar* message, const void*) {
    // Notifications are noise (buffer hints, shader recompiles). Everything at
    // LOW or above is a real defect and is counted.
    if (severity == GL_DEBUG_SEVERITY_NOTIFICATION) return;
    const char* sev = severity == GL_DEBUG_SEVERITY_HIGH   ? "HIGH"
                    : severity == GL_DEBUG_SEVERITY_MEDIUM ? "MEDIUM" : "LOW";
    std::printf("[gl:%s] type=0x%x id=%u %s\n", sev, type, id, message);
    if (g_debug_target) ++g_debug_target->gl_error_count;
}

void glfw_error_callback(int code, const char* description) {
    std::printf("[glfw] error %d: %s\n", code, description);
}

} // namespace

Error gl_context_create(GlContext& c, const GlContextDesc& d) {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit()) return fail(Status::Unsupported, "glfwInit failed");

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_VISIBLE, d.visible ? GLFW_TRUE : GLFW_FALSE);
    if (d.debug) glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GLFW_TRUE);

    c.window = glfwCreateWindow(d.width, d.height, d.title, nullptr, nullptr);
    if (!c.window) {
        glfwTerminate();
        return fail(Status::Unsupported, "glfwCreateWindow failed (no GL 4.6?)");
    }
    glfwMakeContextCurrent(c.window);
    glfwSwapInterval(d.vsync ? 1 : 0);

    if (!gladLoadGL(glfwGetProcAddress)) {
        gl_context_destroy(c);
        return fail(Status::Unsupported, "gladLoadGL failed");
    }

    if (d.debug) {
        g_debug_target = &c;
        glEnable(GL_DEBUG_OUTPUT);
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);   // so the callback names the culprit call
        glDebugMessageCallback(gl_debug_callback, nullptr);
        glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, 0, nullptr, GL_TRUE);
    }

    glfwGetFramebufferSize(c.window, &c.fb_width, &c.fb_height);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;   // no imgui.ini litter in the repo
    ImGui::StyleColorsDark();
    if (!ImGui_ImplGlfw_InitForOpenGL(c.window, true) ||
        !ImGui_ImplOpenGL3_Init("#version 460")) {
        gl_context_destroy(c);
        return fail(Status::Unsupported, "ImGui backend init failed");
    }
    c.imgui_ready = true;

    std::printf("[gl] %s | %s\n", reinterpret_cast<const char*>(glGetString(GL_RENDERER)),
                reinterpret_cast<const char*>(glGetString(GL_VERSION)));
    return ok();
}

void gl_context_destroy(GlContext& c) {
    if (c.imgui_ready) {
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        c.imgui_ready = false;
    }
    if (c.window) { glfwDestroyWindow(c.window); c.window = nullptr; }
    glfwTerminate();
    if (g_debug_target == &c) g_debug_target = nullptr;
}

bool gl_context_should_close(const GlContext& c) {
    return c.window == nullptr || glfwWindowShouldClose(c.window);
}

void gl_context_begin_frame(GlContext& c) {
    glfwPollEvents();
    glfwGetFramebufferSize(c.window, &c.fb_width, &c.fb_height);
    glViewport(0, 0, c.fb_width, c.fb_height);
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();
}

void gl_context_render_ui(GlContext&) {
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

void gl_context_present(GlContext& c) {
    glfwSwapBuffers(c.window);
}

} // namespace astro::render
