#include "clib_openiap.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>

// Default workitem queue
const char* DEFAULT_WIQ = "cqueue";

// Global client
struct ClientWrapper *client = NULL;

// Structure to store file list
typedef struct {
    char **files;
    int count;
    int capacity;
} FileList;

// Function prototypes
void on_connected(void);
void process_workitem(struct WorkitemWrapper *workitem);
void process_workitem_wrapper(FileList *original_files, struct WorkitemWrapper *workitem);
FileList* list_files(void);
void free_file_list(FileList *file_list);
FileList* get_new_files(FileList *original_files);
void cleanup_files(FileList *original_files);
void client_event_callback(struct ClientEventWrapper *event);

// Queue event callback function
const char* queue_event_callback(struct QueueEventWrapper *event) {
    (void)event; // Explicitly mark event as used to avoid warning
    info("Queue event received");
    
    FileList *original_files = list_files();
    if (!original_files) {
        error("Failed to list files");
        return NULL;
    }

    // Pop workitem from the queue
    const char *wiq = getenv("wiq");
    if (!wiq) wiq = DEFAULT_WIQ;

    struct PopWorkitemRequestWrapper pop_req = {
        .wiq = wiq,
        .wiqid = NULL,
        .request_id = 1
    };

    // Try to pop workitems until there are no more
    struct PopWorkitemResponseWrapper *pop_resp;
    int counter = 0;
    
    do {
        info("Popping workitem from queue");
        pop_resp = pop_workitem(client, &pop_req, ".");
        
        if (pop_resp && pop_resp->success && pop_resp->workitem) {
            info("Workitem popped successfully");
            counter++;
            process_workitem_wrapper(original_files, (struct WorkitemWrapper *)pop_resp->workitem);
            free_pop_workitem_response(pop_resp);
            pop_resp = NULL;
        } else {
            info("No more workitems in queue or error occurred");
            if (pop_resp) {
                free_pop_workitem_response(pop_resp);
            }
            break;
        }
        
        // Cleanup files between workitems
        cleanup_files(original_files);
    } while (1);

    if (counter > 0) {
        char log_message[100];
        snprintf(log_message, sizeof(log_message), "No more workitems in %s workitem queue", wiq);
        info(log_message);
    }

    cleanup_files(original_files);
    free_file_list(original_files);
    
    return NULL;
}

// Process a single workitem
void process_workitem(struct WorkitemWrapper *workitem) {
    char log_message[256];
    snprintf(log_message, sizeof(log_message), "Processing workitem id %s, retry #%d", workitem->id, workitem->retries);
    info(log_message);
    
    // Create hello.txt file (example of creating a file during processing)
    FILE *file = fopen("hello.txt", "w");
    if (file) {
        fprintf(file, "Hello kitty");
        fclose(file);
        info("Created hello.txt file");
    } else {
        error("Failed to create hello.txt file");
    }
}

// Wrapper for processing workitems with error handling
void process_workitem_wrapper(FileList *original_files, struct WorkitemWrapper *workitem) {
    // Try to process the workitem
    char log_message[256];
    snprintf(log_message, sizeof(log_message), "Starting processing of workitem %s", workitem->id);
    info(log_message);
    
    // Error handling flag 
    int success = 1;
    
    // Try to process the workitem - in a real application you'd handle exceptions here
    process_workitem(workitem);
    
    if (success) {
        info("Workitem processed successfully");
        // For C strings, we need to allocate and copy
        char *successful_state = strdup("successful");
        if (successful_state) {
            // Need to cast away const to update workitem state
            *((char**)&workitem->state) = successful_state;
        }
    } else {
        info("Workitem processing failed");
        char *retry_state = strdup("retry");
        char *app_error = strdup("application");
        char *error_message = strdup("Processing failed");
        char *error_source = strdup("Unknown source");
        
        if (retry_state && app_error && error_message && error_source) {
            *((char**)&workitem->state) = retry_state;
            *((char**)&workitem->errortype) = app_error;
            *((char**)&workitem->errormessage) = error_message;
            *((char**)&workitem->errorsource) = error_source;
        }
    }
    
    // Get any new files created during processing
    FileList *new_files = get_new_files(original_files);
    
    // Update workitem with new files or just update status
    struct WorkitemFileWrapper **file_wrappers = NULL;
    int files_len = 0;
    
    if (new_files && new_files->count > 0) {
        snprintf(log_message, sizeof(log_message), "Found %d new files to attach", new_files->count);
        info(log_message);
        
        // Create array of file wrappers
        file_wrappers = (struct WorkitemFileWrapper **)malloc(
            sizeof(struct WorkitemFileWrapper *) * new_files->count
        );
        
        if (file_wrappers) {
            for (int i = 0; i < new_files->count; i++) {
                struct WorkitemFileWrapper *file_wrapper = (struct WorkitemFileWrapper *)malloc(
                    sizeof(struct WorkitemFileWrapper)
                );
                
                if (file_wrapper) {
                    file_wrapper->filename = strdup(new_files->files[i]);
                    file_wrapper->id = NULL;
                    file_wrapper->compressed = false;
                    
                    file_wrappers[i] = file_wrapper;
                    files_len++;
                }
            }
        }
    }
    
    // Create update workitem request
    struct UpdateWorkitemRequestWrapper update_req = {
        .workitem = workitem,
        .ignoremaxretries = false,
        .files = (const struct WorkitemFileWrapper *const *)file_wrappers,
        .files_len = files_len,
        .request_id = 2
    };
    
    // Update the workitem
    struct UpdateWorkitemResponseWrapper *update_resp = update_workitem(client, &update_req);
    
    if (update_resp && update_resp->success) {
        info("Workitem updated successfully");
    } else {
        char error_message[256];
        snprintf(error_message, sizeof(error_message), "Failed to update workitem: %s", 
                 update_resp ? update_resp->error : "Unknown error");
        error(error_message);
    }
    
    // Free resources
    if (update_resp) {
        free_update_workitem_response(update_resp);
    }
    
    if (file_wrappers) {
        for (int i = 0; i < files_len; i++) {
            if (file_wrappers[i]) {
                free((void *)file_wrappers[i]->filename);
                free(file_wrappers[i]);
            }
        }
        free(file_wrappers);
    }
    
    if (new_files) {
        free_file_list(new_files);
    }
}

// Get the list of current files
FileList* list_files() {
    DIR *dir;
    struct dirent *entry;
    struct stat file_stat;
    FileList *result = (FileList *)malloc(sizeof(FileList));
    
    if (!result) {
        return NULL;
    }
    
    // Initialize with reasonable capacity
    result->capacity = 10;
    result->count = 0;
    result->files = (char **)malloc(sizeof(char *) * result->capacity);
    
    if (!result->files) {
        free(result);
        return NULL;
    }
    
    // Open current directory
    dir = opendir(".");
    if (!dir) {
        free(result->files);
        free(result);
        return NULL;
    }
    
    // Read all files
    while ((entry = readdir(dir)) != NULL) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        // Check if it's a file
        if (stat(entry->d_name, &file_stat) == 0 && S_ISREG(file_stat.st_mode)) {
            // Resize array if needed
            if (result->count >= result->capacity) {
                result->capacity *= 2;
                char **new_files = (char **)realloc(result->files, sizeof(char *) * result->capacity);
                if (!new_files) {
                    // Handle error
                    for (int i = 0; i < result->count; i++) {
                        free(result->files[i]);
                    }
                    free(result->files);
                    free(result);
                    closedir(dir);
                    return NULL;
                }
                result->files = new_files;
            }
            
            // Add filename to the list
            result->files[result->count] = strdup(entry->d_name);
            result->count++;
        }
    }
    
    closedir(dir);
    return result;
}

// Free file list
void free_file_list(FileList *file_list) {
    if (!file_list) return;
    
    for (int i = 0; i < file_list->count; i++) {
        free(file_list->files[i]);
    }
    
    free(file_list->files);
    free(file_list);
}

// Find new files that were not in the original list
FileList* get_new_files(FileList *original_files) {
    FileList *current_files = list_files();
    FileList *new_files = (FileList *)malloc(sizeof(FileList));
    
    if (!current_files || !new_files) {
        if (current_files) free_file_list(current_files);
        if (new_files) free(new_files);
        return NULL;
    }
    
    new_files->capacity = 10;
    new_files->count = 0;
    new_files->files = (char **)malloc(sizeof(char *) * new_files->capacity);
    
    if (!new_files->files) {
        free_file_list(current_files);
        free(new_files);
        return NULL;
    }
    
    // Find files in current_files that are not in original_files
    for (int i = 0; i < current_files->count; i++) {
        int found = 0;
        
        for (int j = 0; j < original_files->count; j++) {
            if (strcmp(current_files->files[i], original_files->files[j]) == 0) {
                found = 1;
                break;
            }
        }
        
        if (!found) {
            // Resize if needed
            if (new_files->count >= new_files->capacity) {
                new_files->capacity *= 2;
                char **files = (char **)realloc(new_files->files, sizeof(char *) * new_files->capacity);
                if (!files) {
                    free_file_list(current_files);
                    free_file_list(new_files);
                    return NULL;
                }
                new_files->files = files;
            }
            
            new_files->files[new_files->count] = strdup(current_files->files[i]);
            new_files->count++;
        }
    }
    
    free_file_list(current_files);
    return new_files;
}

// Delete files that were not in the original list
void cleanup_files(FileList *original_files) {
    FileList *new_files = get_new_files(original_files);
    
    if (!new_files) {
        return;
    }
    
    for (int i = 0; i < new_files->count; i++) {
        char log_message[256];
        snprintf(log_message, sizeof(log_message), "Deleting file: %s", new_files->files[i]);
        info(log_message);
        unlink(new_files->files[i]);
    }
    
    free_file_list(new_files);
}

// Client event callback
void client_event_callback(struct ClientEventWrapper *event) {
    if (event && event->event && strcmp(event->event, "SignedIn") == 0) {
        info("Signed in successfully, connecting to queue");
        on_connected();
    }
}

// Called when connected to the server and signed in
void on_connected() {
    const char *wiq = getenv("wiq");
    const char *queue = getenv("queue");
    
    if (!wiq) wiq = DEFAULT_WIQ;
    if (!queue) queue = wiq;
    
    char log_message[256];
    snprintf(log_message, sizeof(log_message), "Registering queue: %s", queue);
    info(log_message);
    
    // Register queue
    struct RegisterQueueRequestWrapper req = {
        .queuename = queue,
        .request_id = 1
    };
    
    struct RegisterQueueResponseWrapper *resp = register_queue_async(client, &req, queue_event_callback);
    
    if (resp && resp->success) {
        char queue_message[256];
        snprintf(queue_message, sizeof(queue_message), "Consuming queue: %s", resp->queuename);
        info(queue_message);
    } else {
        char error_message[256];
        snprintf(error_message, sizeof(error_message), "Failed to register queue: %s", 
                resp ? resp->error : "Unknown error");
        error(error_message);
    }
    
    if (resp) {
        free_register_queue_response(resp);
    }
}

int main() {
    // Enable tracing
    enable_tracing("openiap=info", "");
    
    // Create client
    client = create_client();
    if (!client) {
        error("Failed to create client");
        return 1;
    }
    
    // Connect to server
    info("Connecting to OpenIAP server...");
    struct ConnectResponseWrapper *connect_resp = client_connect(client, "");
    if (!connect_resp || !connect_resp->success) {
        char error_message[256];
        snprintf(error_message, sizeof(error_message), "Failed to connect: %s", 
                connect_resp ? connect_resp->error : "Unknown error");
        error(error_message);
        free_client(client);
        return 1;
    }
    info("Connected successfully");
    free_connect_response(connect_resp);

    // Register client event callback
    struct ClientEventResponseWrapper *event_resp = on_client_event_async(client, client_event_callback);
    if (!event_resp || !event_resp->success) {
        error("Failed to register client event callback");
        free_client(client);
        return 1;
    }
    if (event_resp) {
        char log_message[256];
        snprintf(log_message, sizeof(log_message), "Client event callback registered: %s", 
                event_resp->eventid);
        info(log_message);
        free_event_response(event_resp); // Corrected function name based on compiler suggestion
    } else {
        error("Failed to register client event callback");
        free_client(client);
        return 1;
    }
    
    
    // Keep the program running - in a real application, you would use a proper event loop
    // or integration with your application's main loop
    info("Press Ctrl+C to exit");
    while (1) {
        sleep(1);
    }
    
    // Cleanup
    client_disconnect(client);
    free_client(client);
    
    return 0;
}